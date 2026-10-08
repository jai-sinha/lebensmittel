package websocket

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow connections from any origin
		return true
	},
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

const (
	// time allowed to write a message to the peer
	writeWait = 10 * time.Second

	// time allowed to read the next pong message from the peer
	pongWait = 15 * time.Second

	// send pings to peer with this period (must be less than pongWait)
	pingPeriod = (pongWait * 9) / 10

	// maximum message size allowed from peer
	maxMessageSize = 512 * 1024
)

type Client struct {
	Conn    *websocket.Conn
	Groups  map[string]bool // Set of group IDs
	writeMu sync.Mutex      // Serializes data-frame writes (broadcasts, welcome)
}

type BroadcastMessage struct {
	Data    []byte
	GroupID string
}

type Subscription struct {
	Client   *websocket.Conn
	GroupIDs []string
}

type WebSocketManager struct {
	clients    map[*websocket.Conn]*Client
	groups     map[string]map[*websocket.Conn]bool // groupID -> set of connections
	broadcast  chan BroadcastMessage
	register   chan *Client
	unregister chan *websocket.Conn
	subscribe  chan Subscription
	mutex      sync.RWMutex
}

func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		clients:    make(map[*websocket.Conn]*Client),
		groups:     make(map[string]map[*websocket.Conn]bool),
		broadcast:  make(chan BroadcastMessage, 256),
		register:   make(chan *Client),
		unregister: make(chan *websocket.Conn),
		subscribe:  make(chan Subscription),
	}
}

func (manager *WebSocketManager) Run() {
	for {
		select {
		case client := <-manager.register:
			manager.mutex.Lock()
			manager.clients[client.Conn] = client
			// register to groups
			for groupID := range client.Groups {
				if _, ok := manager.groups[groupID]; !ok {
					manager.groups[groupID] = make(map[*websocket.Conn]bool)
				}
				manager.groups[groupID][client.Conn] = true
			}
			manager.mutex.Unlock()
			log.Printf("Client connected: Groups=%v", client.Groups)

			welcomeMsg := map[string]any{
				"event": "connected",
				"data":  map[string]string{"message": "Connected to Lebensmittel backend"},
			}
			msgBytes, _ := json.Marshal(welcomeMsg)
			client.writeMu.Lock()
			client.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			client.Conn.WriteMessage(websocket.TextMessage, msgBytes)
			client.writeMu.Unlock()

		case sub := <-manager.subscribe:
			manager.mutex.Lock()
			if client, ok := manager.clients[sub.Client]; ok {
				for _, groupID := range sub.GroupIDs {
					// map the clients and groups
					client.Groups[groupID] = true
					if _, ok := manager.groups[groupID]; !ok {
						manager.groups[groupID] = make(map[*websocket.Conn]bool)
					}
					manager.groups[groupID][sub.Client] = true
				}
				log.Printf("Client subscribed to groups: %v", sub.GroupIDs)
			}
			manager.mutex.Unlock()

		case conn := <-manager.unregister:
			manager.mutex.Lock()
			if client, ok := manager.clients[conn]; ok {
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

			// use a set to avoid sending duplicate messages to the same connection
			targetConns := make(map[*websocket.Conn]bool)

			if conns, ok := manager.groups[message.GroupID]; ok {
				for conn := range conns {
					targetConns[conn] = true
				}
			}

			for conn := range targetConns {
				if client, ok := manager.clients[conn]; ok {
					client.writeMu.Lock()
					conn.SetWriteDeadline(time.Now().Add(writeWait))
					err := conn.WriteMessage(websocket.TextMessage, message.Data)
					client.writeMu.Unlock()
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

// sends an event to connected WebSocket clients, scoped by groupID
func (manager *WebSocketManager) EmitEvent(event string, payload any, groupID string) {
	message := map[string]any{
		"event": event,
		"data":  payload,
	}

	msgBytes, err := json.Marshal(message)
	if err != nil {
		log.Printf("[socketio] Failed to marshal event %s: %v", event, err)
		return
	}

	log.Printf("[socketio] Emitting %s -> %v (Groups: %v)", event, payload, groupID)

	select {
	case manager.broadcast <- BroadcastMessage{Data: msgBytes, GroupID: groupID}:
		log.Printf("[socketio] Emitted %s", event)
	default:
		log.Printf("[socketio] Emit failed for %s: broadcast channel full", event)
	}
}

func (manager *WebSocketManager) HandleWebSocket(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade connection: %v", err)
		return
	}

	requestedGroups := c.Query("groups")
	initialGroups := make(map[string]bool)

	if requestedGroups != "" {
		for gid := range strings.SplitSeq(requestedGroups, ",") {
			gid = strings.TrimSpace(gid)
			if gid != "" {
				initialGroups[gid] = true
			}
		}
	}

	client := &Client{
		Conn:   conn,
		Groups: initialGroups,
	}

	// configure connection
	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	manager.register <- client

	ticker := time.NewTicker(pingPeriod)

	// handle outgoing pings — WriteControl is safe for concurrent use with WriteMessage
	go func() {
		defer ticker.Stop()
		for range ticker.C {
			if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(writeWait)); err != nil {
				return
			}
		}
	}()

	// incoming message handler
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
					// handle specific message types
					if event, ok := msg["event"].(string); ok {
						switch event {
						case "subscribe":
							// handle subscriptions
							if data, ok := msg["data"].(map[string]any); ok {
								if groupsInterface, ok := data["groups"].([]any); ok {
									var groupIDs []string
									for _, g := range groupsInterface {
										if s, ok := g.(string); ok {
											groupIDs = append(groupIDs, s)
										}
									}

									var requested []string
									for _, gid := range groupIDs {
										gid = strings.TrimSpace(gid)
										if gid != "" {
											requested = append(requested, gid)
										}
									}

									if len(requested) > 0 {
										manager.subscribe <- Subscription{Client: conn, GroupIDs: requested}
									}
								}
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

// global WebSocket manager instance
var wsManager *WebSocketManager

func InitWebSocketManager() {
	wsManager = NewWebSocketManager()
	go wsManager.Run()
}

// helper function to emit events using the global manager
func EmitEvent(event string, payload any, groupID string) {
	if wsManager != nil {
		wsManager.EmitEvent(event, payload, groupID)
	}
}

func HandleWebSocket(c *gin.Context) {
	if wsManager != nil {
		wsManager.HandleWebSocket(c)
	}
}
