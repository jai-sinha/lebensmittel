# Lebensmittel Backend - Go Implementation

This is a Go implementation of the Lebensmittel backend API, migrated from Python Flask to Go with Gin framework and PostgreSQL database.

## Features

- **REST API** for managing grocery items, meal plans, and receipts
- **WebSocket support** for real-time updates using gorilla/websocket
- **PostgreSQL database** with connection pooling
- **CORS enabled** for cross-origin requests
- **JSON API** compatible with the iOS Swift frontend

## Tech Stack

- **Go 1.24+**
- **Gin** - HTTP web framework
- **PostgreSQL** - Database
- **pgx/v5** - PostgreSQL driver with connection pooling
- **gorilla/websocket** - Native WebSocket implementation (replaces Socket.IO)
- **UUID** - For generating unique IDs


## Installation

1. Clone the repository and navigate to the Go backend directory:
```bash
cd backend/go
```

2. Install dependencies:
```bash
go mod tidy
```

3. Build the application:
```bash
go build
```

## Configuration

The application uses environment variables for configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://jsinha:@localhost/lebensmittel` |
| `PORT` | Server port | `8000` |
| `SECRET_KEY` | Secret key for sessions | `your-secret-key-here` |
| `DEBUG` | Enable debug mode | `false` |

## Database Schema

The application expects the following PostgreSQL tables:

### grocery_items
```sql
CREATE TABLE grocery_items (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    is_needed BOOLEAN DEFAULT true,
    is_shopping_checked BOOLEAN DEFAULT false
);
```

### meal_plans
```sql
CREATE TABLE meal_plans (
    id VARCHAR(36) PRIMARY KEY,
    date DATE NOT NULL,
    meal_description TEXT NOT NULL
);
```

### receipts
```sql
CREATE TABLE receipts (
    id VARCHAR(36) PRIMARY KEY,
    date DATE NOT NULL,
    total_amount FLOAT NOT NULL,
    purchased_by VARCHAR(50) NOT NULL,
    items TEXT,
    notes TEXT
);
```

## API Endpoints

### Grocery Items
- `GET /api/grocery-items` - Get all grocery items
- `POST /api/grocery-items` - Create a new grocery item
- `PUT /api/grocery-items/:id` - Update a grocery item
- `DELETE /api/grocery-items/:id` - Delete a grocery item

### Meal Plans
- `GET /api/meal-plans` - Get all meal plans
- `POST /api/meal-plans` - Create a new meal plan
- `PUT /api/meal-plans/:id` - Update a meal plan
- `DELETE /api/meal-plans/:id` - Delete a meal plan

### Receipts
- `GET /api/receipts` - Get all receipts
- `POST /api/receipts` - Create a new receipt
- `PUT /api/receipts/:id` - Update a receipt
- `DELETE /api/receipts/:id` - Delete a receipt

### Other
- `GET /` - API information
- `GET /health` - Health check
- `GET /ws` - WebSocket connection

## WebSocket Events

The WebSocket endpoint (`/ws`) supports real-time updates using native WebSockets.

### Message Format

All WebSocket messages use this JSON structure:
```json
{
  "event": "event_name",
  "data": { /* payload */ }
}
```

### Client → Server Events
- `echo` - Echo message back to client (for testing)

### Server → Client Events
- `connected` - Welcome message on connection
- `grocery_item_created` - New grocery item created
- `grocery_item_updated` - Grocery item updated
- `grocery_item_deleted` - Grocery item deleted (data: `{"id": "..."}`)
- `meal_plan_created` - New meal plan created
- `meal_plan_updated` - Meal plan updated
- `meal_plan_deleted` - Meal plan deleted (data: `{"id": "..."}`)
- `receipt_created` - New receipt created
- `receipt_updated` - Receipt updated
- `receipt_deleted` - Receipt deleted (data: `{"id": "..."}`)

### Connection Keep-Alive

The WebSocket implementation includes automatic ping/pong:
- **Ping Interval**: Every 54 seconds
- **Pong Timeout**: 60 seconds
- Connections that don't respond to pings are automatically closed

## Project Structure

```
.
├── main.go           # Main application entry point and HTTP handlers
├── models.go         # Data models and structures
├── database.go       # Database connection and CRUD operations
├── websocket.go      # WebSocket manager and handlers
├── config.go         # Configuration management
├── go.mod            # Go module dependencies
├── go.sum            # Go module checksums
└── README.md         # This file
```

## Migration from Python

This Go implementation maintains API compatibility with the original Python Flask version:

- **Same endpoints** and request/response formats
- **Same database schema** (migrated from SQLite to PostgreSQL)
- **Same WebSocket events** for real-time updates
- **Same business logic** for receipt creation and grocery item management

### Key Differences

1. **Database**: Migrated from SQLite to PostgreSQL
2. **WebSocket**: Uses gorilla/websocket (native WebSocket protocol) instead of Flask-SocketIO
   - Standard WebSocket protocol (RFC 6455)
   - No Socket.IO protocol overhead
   - Compatible with Starscream (iOS client)
3. **JSON handling**: Native Go JSON marshaling with custom serialization
4. **Connection pooling**: Built-in PostgreSQL connection pooling with pgxpool
5. **Performance**: Significantly improved performance and concurrency
6. **Message Format**: Standardized `{"event": "...", "data": {...}}` structure

## WebSocket Client Compatibility

The WebSocket implementation is compatible with:
- **Starscream** (iOS/Swift) - Recommended
- **Native WebSocket API** (JavaScript browsers)
- Any standard WebSocket client library

**Note**: This implementation uses native WebSockets, NOT Socket.IO. Socket.IO clients will not work without modification.

For iOS client setup, see `WEBSOCKET_MIGRATION.md` in the project root.
