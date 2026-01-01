package websocket

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/lebensmittel/backend/auth"
	"github.com/lebensmittel/backend/database"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow connections from any origin (adjust for production)
		return true
	},
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

const (
	// Time allowed to write a message to the peer
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer
	pongWait = 60 * time.Second

	// Send pings to peer with this period (must be less than pongWait)
	pingPeriod = (pongWait * 9) / 10

	// Maximum message size allowed from peer
	maxMessageSize = 512 * 1024
)

// Client represents a connected WebSocket client
type Client struct {
	Conn   *websocket.Conn
	UserID string
	Groups map[string]bool // Set of group IDs
}

// BroadcastMessage represents a message to be sent to clients
type BroadcastMessage struct {
	Data     []byte
	GroupIDs []string // Optional: if empty, broadcast to all (legacy)
}

// Subscription represents a request to subscribe to groups
type Subscription struct {
	Client   *websocket.Conn
	GroupIDs []string
}

// WebSocketManager manages WebSocket connections
type WebSocketManager struct {
	clients    map[*websocket.Conn]*Client
	groups     map[string]map[*websocket.Conn]bool // groupID -> set of connections
	broadcast  chan BroadcastMessage
	register   chan *Client
	unregister chan *websocket.Conn
	subscribe  chan Subscription
	mutex      sync.RWMutex
}

// NewWebSocketManager creates a new WebSocket manager
func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		clients:    make(map[*websocket.Conn]*Client),
		groups:     make(map[string]map[*websocket.Conn]bool),
		broadcast:  make(chan BroadcastMessage),
		register:   make(chan *Client),
		unregister: make(chan *websocket.Conn),
		subscribe:  make(chan Subscription),
	}
}

// Run starts the WebSocket manager
func (manager *WebSocketManager) Run() {
	for {
		select {
		case client := <-manager.register:
			manager.mutex.Lock()
			manager.clients[client.Conn] = client
			// Register to groups
			for groupID := range client.Groups {
				if _, ok := manager.groups[groupID]; !ok {
					manager.groups[groupID] = make(map[*websocket.Conn]bool)
				}
				manager.groups[groupID][client.Conn] = true
			}
			manager.mutex.Unlock()
			log.Printf("Client connected: UserID=%s, Groups=%v", client.UserID, client.Groups)

			// Send welcome message
			welcomeMsg := map[string]any{
				"event": "connected",
				"data":  map[string]string{"message": "Connected to Lebensmittel backend"},
			}
			msgBytes, _ := json.Marshal(welcomeMsg)
			client.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			client.Conn.WriteMessage(websocket.TextMessage, msgBytes)

		case sub := <-manager.subscribe:
			manager.mutex.Lock()
			if client, ok := manager.clients[sub.Client]; ok {
				for _, groupID := range sub.GroupIDs {
					// Add to client's group list
					client.Groups[groupID] = true
					// Add to manager's group map
					if _, ok := manager.groups[groupID]; !ok {
						manager.groups[groupID] = make(map[*websocket.Conn]bool)
					}
					manager.groups[groupID][sub.Client] = true
				}
				log.Printf("Client %s subscribed to groups: %v", client.UserID, sub.GroupIDs)
			}
			manager.mutex.Unlock()

		case conn := <-manager.unregister:
			manager.mutex.Lock()
			if client, ok := manager.clients[conn]; ok {
				// Remove from all groups
				for groupID := range client.Groups {
					if _, ok := manager.groups[groupID]; ok {
						delete(manager.groups[groupID], conn)
						if len(manager.groups[groupID]) == 0 {
							delete(manager.groups, groupID)
						}
					}
				}
				delete(manager.clients, conn)
				conn.Close()
			}
			manager.mutex.Unlock()
			log.Println("Client disconnected")

		case message := <-manager.broadcast:
			manager.mutex.RLock()

			// If GroupIDs are provided, broadcast only to those groups
			if len(message.GroupIDs) > 0 {
				// Use a set to avoid sending duplicate messages to the same connection
				targetConns := make(map[*websocket.Conn]bool)

				for _, groupID := range message.GroupIDs {
					if conns, ok := manager.groups[groupID]; ok {
						for conn := range conns {
							targetConns[conn] = true
						}
					}
				}

				for conn := range targetConns {
					conn.SetWriteDeadline(time.Now().Add(writeWait))
					err := conn.WriteMessage(websocket.TextMessage, message.Data)
					if err != nil {
						log.Printf("Error writing message: %v", err)
						conn.Close()
					}
				}
			} else {
				// Broadcast to all (legacy behavior)
				for conn := range manager.clients {
					conn.SetWriteDeadline(time.Now().Add(writeWait))
					err := conn.WriteMessage(websocket.TextMessage, message.Data)
					if err != nil {
						log.Printf("Error writing message: %v", err)
						conn.Close()
					}
				}
			}
			manager.mutex.RUnlock()
		}
	}
}

// EmitEvent sends an event to connected WebSocket clients
// If groupIDs are provided, it sends only to clients subscribed to those groups
func (manager *WebSocketManager) EmitEvent(event string, payload any, groupIDs ...string) {
	message := map[string]any{
		"event": event,
		"data":  payload,
	}

	msgBytes, err := json.Marshal(message)
	if err != nil {
		log.Printf("[socketio] Failed to marshal event %s: %v", event, err)
		return
	}

	log.Printf("[socketio] Emitting %s -> %v (Groups: %v)", event, payload, groupIDs)

	select {
	case manager.broadcast <- BroadcastMessage{Data: msgBytes, GroupIDs: groupIDs}:
		log.Printf("[socketio] Emitted %s", event)
	default:
		log.Printf("[socketio] Emit failed for %s: broadcast channel full", event)
	}
}

// HandleWebSocket handles WebSocket connections
func (manager *WebSocketManager) HandleWebSocket(c *gin.Context) {
	// 1. Authenticate
	tokenString := c.Query("token")
	if tokenString == "" {
		// Try getting from header if not in query
		authHeader := c.GetHeader("Authorization")
		if len(authHeader) > 7 && strings.ToUpper(authHeader[0:7]) == "BEARER " {
			tokenString = authHeader[7:]
		}
	}

	if tokenString == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing token"})
		return
	}

	claims, err := auth.ValidateToken(tokenString)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
		return
	}

	userID := claims.UserID

	// 2. Upgrade connection
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade connection: %v", err)
		return
	}

	// 3. Determine initial groups
	// Client can pass ?groups=id1,id2
	requestedGroups := c.Query("groups")
	initialGroups := make(map[string]bool)

	if requestedGroups != "" {
		groupIDs := strings.Split(requestedGroups, ",")
		// Verify membership
		userGroups, err := database.GetUserGroups(context.Background(), userID)
		if err == nil {
			validGroupMap := make(map[string]bool)
			for _, g := range userGroups {
				validGroupMap[g.ID] = true
			}

			for _, gid := range groupIDs {
				gid = strings.TrimSpace(gid)
				if validGroupMap[gid] {
					initialGroups[gid] = true
				}
			}
		}
	}

	client := &Client{
		Conn:   conn,
		UserID: userID,
		Groups: initialGroups,
	}

	// Configure connection
	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	manager.register <- client

	// Start ping ticker for keep-alive
	ticker := time.NewTicker(pingPeriod)

	// Handle outgoing pings
	go func() {
		defer ticker.Stop()
		for range ticker.C {
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}()

	// Handle incoming messages
	go func() {
		defer func() {
			ticker.Stop()
			manager.unregister <- conn
		}()

		for {
			messageType, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("WebSocket error: %v", err)
				}
				break
			}

			if messageType == websocket.TextMessage {
				var msg map[string]any
				if err := json.Unmarshal(message, &msg); err == nil {
					// Handle specific message types
					if event, ok := msg["event"].(string); ok {
						switch event {
						case "subscribe":
							// Handle subscription to groups
							if data, ok := msg["data"].(map[string]any); ok {
								if groupsInterface, ok := data["groups"].([]any); ok {
									var groupIDs []string
									for _, g := range groupsInterface {
										if s, ok := g.(string); ok {
											groupIDs = append(groupIDs, s)
										}
									}

									// Verify membership
									userGroups, err := database.GetUserGroups(context.Background(), userID)
									if err == nil {
										validGroupMap := make(map[string]bool)
										for _, g := range userGroups {
											validGroupMap[g.ID] = true
										}

										var validIDs []string
										for _, gid := range groupIDs {
											if validGroupMap[gid] {
												validIDs = append(validIDs, gid)
											}
										}

										if len(validIDs) > 0 {
											manager.subscribe <- Subscription{Client: conn, GroupIDs: validIDs}
										}
									}
								}
							}
						case "echo":
							// Echo message back to client
							if _, ok := msg["data"]; ok {
								echoMsg := map[string]any{
									"event": "echo",
									"data":  msg["data"],
								}
								echoBytes, _ := json.Marshal(echoMsg)
								conn.SetWriteDeadline(time.Now().Add(writeWait))
								conn.WriteMessage(websocket.TextMessage, echoBytes)
								log.Printf("Echoed message: %v", msg["data"])
							}
						default:
							log.Printf("Received unknown event: %s", event)
						}
					}
				} else {
					log.Printf("Failed to parse WebSocket message: %v", err)
				}
			}
		}
	}()
}

// Global WebSocket manager instance
var wsManager *WebSocketManager

// InitWebSocketManager initializes the global WebSocket manager
func InitWebSocketManager() {
	wsManager = NewWebSocketManager()
	go wsManager.Run()
}

// EmitEvent is a helper function to emit events using the global manager
func EmitEvent(event string, payload any, groupIDs ...string) {
	if wsManager != nil {
		wsManager.EmitEvent(event, payload, groupIDs...)
	}
}

// HandleWebSocket handles WebSocket requests using the global manager
func HandleWebSocket(c *gin.Context) {
	if wsManager != nil {
		wsManager.HandleWebSocket(c)
	}
}
