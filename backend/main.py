from flask import Flask, jsonify, request
from database import init_db, SessionLocal
from models import GroceryItem, MealPlan
from datetime import datetime

# Create Flask application instance
app = Flask(__name__)

# Initialize database on startup
with app.app_context():
    init_db()

@app.route('/')
def home():
    """Home route that returns a welcome message."""
    return jsonify({
        'message': 'Welcome to the Lebensmittel Backend API',
        'status': 'success',
        'version': '1.0.0'
    })

@app.route('/health')
def health_check():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'message': 'Service is running'
    })

@app.route('/api/grocery-items', methods=['GET'])
def get_grocery_items():
    """Get all grocery items."""
    db = SessionLocal()
    try:
        items = db.query(GroceryItem).all()
        return jsonify({
            'groceryItems': [item.to_dict() for item in items],
            'count': len(items)
        })
    finally:
        db.close()


@app.route('/api/grocery-items', methods=['POST'])
def create_grocery_item():
    """Create a new grocery item."""
    data = request.get_json()
    
    if not data or 'name' not in data or 'category' not in data:
        return jsonify({'error': 'Name and category are required'}), 400
    
    db = SessionLocal()
    try:
        new_item = GroceryItem(
            name=data['name'],
            category=data['category'],
            is_needed=data.get('isNeeded', True),
            is_shopping_checked=data.get('isShoppingChecked', False)
        )
        db.add(new_item)
        db.commit()
        db.refresh(new_item)
        
        return jsonify(new_item.to_dict()), 201
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/grocery-items/<item_id>', methods=['PUT'])
def update_grocery_item(item_id):
    """Update a grocery item."""
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    db = SessionLocal()
    try:
        item = db.query(GroceryItem).filter(GroceryItem.id == item_id).first()
        if not item:
            return jsonify({'error': 'Grocery item not found'}), 404
        
        # Update fields if provided
        if 'name' in data:
            item.name = data['name']
        if 'category' in data:
            item.category = data['category']
        if 'isNeeded' in data:
            item.is_needed = data['isNeeded']
        if 'isShoppingChecked' in data:
            item.is_shopping_checked = data['isShoppingChecked']
        
        db.commit()
        db.refresh(item)
        
        return jsonify(item.to_dict())
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/grocery-items/<item_id>', methods=['DELETE'])
def delete_grocery_item(item_id):
    """Delete a grocery item."""
    db = SessionLocal()
    try:
        item = db.query(GroceryItem).filter(GroceryItem.id == item_id).first()
        if not item:
            return jsonify({'error': 'Grocery item not found'}), 404
        
        db.delete(item)
        db.commit()
        
        return jsonify({'message': 'Grocery item deleted successfully'})
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/meal-plans', methods=['GET'])
def get_meal_plans():
    """Get all meal plans."""
    db = SessionLocal()
    try:
        meals = db.query(MealPlan).order_by(MealPlan.date).all()
        return jsonify({
            'mealPlans': [meal.to_dict() for meal in meals],
            'count': len(meals)
        })
    finally:
        db.close()


@app.route('/api/meal-plans', methods=['POST'])
def create_meal_plan():
    """Create a new meal plan."""
    data = request.get_json()
    
    if not data or 'date' not in data or 'mealDescription' not in data:
        return jsonify({'error': 'Date and mealDescription are required'}), 400
    
    db = SessionLocal()
    try:
        # Parse date string to datetime
        try:
            date = datetime.fromisoformat(data['date'].replace('Z', '+00:00'))
        except ValueError:
            return jsonify({'error': 'Invalid date format. Use ISO format (YYYY-MM-DDTHH:MM:SS)'}), 400
        
        new_meal = MealPlan(
            date=date,
            meal_description=data['mealDescription']
        )
        db.add(new_meal)
        db.commit()
        db.refresh(new_meal)
        
        return jsonify(new_meal.to_dict()), 201
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/meal-plans/<meal_id>', methods=['PUT'])
def update_meal_plan(meal_id):
    """Update a meal plan."""
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    db = SessionLocal()
    try:
        meal = db.query(MealPlan).filter(MealPlan.id == meal_id).first()
        if not meal:
            return jsonify({'error': 'Meal plan not found'}), 404
        
        # Update fields if provided
        if 'date' in data:
            try:
                meal.date = datetime.fromisoformat(data['date'].replace('Z', '+00:00'))
            except ValueError:
                return jsonify({'error': 'Invalid date format. Use ISO format (YYYY-MM-DDTHH:MM:SS)'}), 400
        
        if 'mealDescription' in data:
            meal.meal_description = data['mealDescription']
        
        db.commit()
        db.refresh(meal)
        
        return jsonify(meal.to_dict())
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/meal-plans/<meal_id>', methods=['DELETE'])
def delete_meal_plan(meal_id):
    """Delete a meal plan."""
    db = SessionLocal()
    try:
        meal = db.query(MealPlan).filter(MealPlan.id == meal_id).first()
        if not meal:
            return jsonify({'error': 'Meal plan not found'}), 404
        
        db.delete(meal)
        db.commit()
        
        return jsonify({'message': 'Meal plan deleted successfully'})
    except Exception as e:
        db.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        db.close()


@app.route('/api/products')
def get_products():
    """Legacy endpoint - redirects to grocery items."""
    return get_grocery_items()

if __name__ == '__main__':
    # Run the Flask development server
    app.run(debug=True, host='0.0.0.0', port=8000)