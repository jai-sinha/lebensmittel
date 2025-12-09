package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow connections from any origin (adjust for production)
		return true
	},
}

// WebSocketManager manages WebSocket connections
type WebSocketManager struct {
	connections map[*websocket.Conn]bool
	broadcast   chan []byte
	register    chan *websocket.Conn
	unregister  chan *websocket.Conn
	mutex       sync.RWMutex
}

// NewWebSocketManager creates a new WebSocket manager
func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		connections: make(map[*websocket.Conn]bool),
		broadcast:   make(chan []byte),
		register:    make(chan *websocket.Conn),
		unregister:  make(chan *websocket.Conn),
	}
}

// Run starts the WebSocket manager
func (manager *WebSocketManager) Run() {
	for {
		select {
		case conn := <-manager.register:
			manager.mutex.Lock()
			manager.connections[conn] = true
			manager.mutex.Unlock()
			log.Println("Client connected")

			// Send welcome message
			welcomeMsg := map[string]interface{}{
				"event": "connected",
				"data":  map[string]string{"message": "Connected to Lebensmittel backend"},
			}
			msgBytes, _ := json.Marshal(welcomeMsg)
			conn.WriteMessage(websocket.TextMessage, msgBytes)

		case conn := <-manager.unregister:
			manager.mutex.Lock()
			if _, ok := manager.connections[conn]; ok {
				delete(manager.connections, conn)
				conn.Close()
			}
			manager.mutex.Unlock()
			log.Println("Client disconnected")

		case message := <-manager.broadcast:
			manager.mutex.RLock()
			for conn := range manager.connections {
				err := conn.WriteMessage(websocket.TextMessage, message)
				if err != nil {
					log.Printf("Error writing message: %v", err)
					conn.Close()
					delete(manager.connections, conn)
				}
			}
			manager.mutex.RUnlock()
		}
	}
}

// EmitEvent sends an event to all connected WebSocket clients
func (manager *WebSocketManager) EmitEvent(event string, payload interface{}) {
	message := map[string]interface{}{
		"event": event,
		"data":  payload,
	}

	msgBytes, err := json.Marshal(message)
	if err != nil {
		log.Printf("[socketio] Failed to marshal event %s: %v", event, err)
		return
	}

	log.Printf("[socketio] Emitting %s -> %v", event, payload)

	select {
	case manager.broadcast <- msgBytes:
		log.Printf("[socketio] Emitted %s", event)
	default:
		log.Printf("[socketio] Emit failed for %s: broadcast channel full", event)
	}
}

// HandleWebSocket handles WebSocket connections
func (manager *WebSocketManager) HandleWebSocket(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade connection: %v", err)
		return
	}

	manager.register <- conn

	// Handle incoming messages
	go func() {
		defer func() {
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
				var msg map[string]interface{}
				if err := json.Unmarshal(message, &msg); err == nil {
					// Handle specific message types
					if event, ok := msg["event"].(string); ok {
						switch event {
						case "echo":
							// Echo message back to client
							if data, ok := msg["data"]; ok {
								conn.WriteMessage(websocket.TextMessage, message)
								log.Printf("Echoed message: %v", data)
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
func EmitEvent(event string, payload interface{}) {
	if wsManager != nil {
		wsManager.EmitEvent(event, payload)
	}
}
