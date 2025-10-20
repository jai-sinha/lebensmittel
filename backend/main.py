from flask import Flask, jsonify, request
from flask_cors import CORS
from database import init_db, SessionLocal
from models import GroceryItem, MealPlan, Receipts
from datetime import datetime
import json

app = Flask(__name__)
CORS(app)

# Initialize database on startup
with app.app_context():
	init_db()

@app.route('/')
def home():
	"""Home route that returns a welcome message."""
	api_routes = [
		{'route': '/', 'methods': ['GET'], 'description': 'Home route (API info)'},
		{'route': '/health', 'methods': ['GET'], 'description': 'Health check'},
		{'route': '/api/grocery-items', 'methods': ['GET'], 'description': 'Get all grocery items'},
		{'route': '/api/grocery-items', 'methods': ['POST'], 'description': 'Create a grocery item'},
		{'route': '/api/grocery-items/<item_id>', 'methods': ['PUT'], 'description': 'Update a grocery item'},
		{'route': '/api/grocery-items/<item_id>', 'methods': ['DELETE'], 'description': 'Delete a grocery item'},
		{'route': '/api/meal-plans', 'methods': ['GET'], 'description': 'Get all meal plans'},
		{'route': '/api/meal-plans', 'methods': ['POST'], 'description': 'Create a meal plan'},
		{'route': '/api/meal-plans/<meal_id>', 'methods': ['PUT'], 'description': 'Update a meal plan'},
		{'route': '/api/meal-plans/<meal_id>', 'methods': ['DELETE'], 'description': 'Delete a meal plan'},
		{'route': '/api/receipts', 'methods': ['GET'], 'description': 'Get all receipts'},
		{'route': '/api/receipts', 'methods': ['POST'], 'description': 'Create a receipt'},
		{'route': '/api/receipts/<receipt_id>', 'methods': ['PUT'], 'description': 'Update a receipt'},
		{'route': '/api/receipts/<receipt_id>', 'methods': ['DELETE'], 'description': 'Delete a receipt'},
	]
	return jsonify({
		'message': 'Welcome to the Lebensmittel Backend API',
		'status': 'success',
		'version': '1.0.0',
		'apiRoutes': api_routes
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
	"""Create a new meal plan. Enforces only one meal per date."""
	data = request.get_json()
	
	if not data or 'date' not in data or 'mealDescription' not in data:
		return jsonify({'error': 'Date and mealDescription are required'}), 400
	
	db = SessionLocal()
	try:
		# Parse date string to date
		try:
			date = datetime.strptime(data['date'], '%Y-%m-%d').date()
		except (ValueError, TypeError):
			return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400

		# Remove any existing meal for this date
		db.query(MealPlan).filter(MealPlan.date == date).delete()

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
				meal.date = datetime.strptime(data['date'], '%Y-%m-%d').date()
			except (ValueError, TypeError):
				return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400

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


@app.route('/api/receipts', methods=['GET'])
def get_receipts():
	"""Get all receipts."""
	db = SessionLocal()
	try:
		receipts = db.query(Receipts).order_by(Receipts.date.desc()).all()
		return jsonify({
			'receipts': [receipt.to_dict() for receipt in receipts],
			'count': len(receipts)
		})
	finally:
		db.close()


@app.route('/api/receipts', methods=['POST'])
def create_receipt():
	"""Create a new receipt."""
	data = request.get_json()

	required_fields = ['date', 'totalAmount', 'purchasedBy']
	if not data or not all(field in data for field in required_fields):
		return jsonify({'error': 'date, totalAmount, and purchasedBy are required'}), 400

	db = SessionLocal()
	try:
		# parse date
		try:
			date = datetime.strptime(data['date'], '%Y-%m-%d').date()
		except (ValueError, TypeError):
			return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400

		# Gather all grocery items that are needed and checked
		items_to_checkout = db.query(GroceryItem).filter(
			GroceryItem.is_needed == True,
			GroceryItem.is_shopping_checked == True
		).all()

		# If there are no items to checkout, reject the request
		if not items_to_checkout:
			return jsonify({'error': 'No grocery items are both needed and checked; receipt would be empty.'}), 400

		# Extract names for receipt and unset flags on the items
		item_names = [item.name for item in items_to_checkout]
		for gi in items_to_checkout:
			gi.is_needed = False
			gi.is_shopping_checked = False

		items_json = json.dumps(item_names)

		new_receipt = Receipts(
			date=date,
			total_amount=data['totalAmount'],
			purchased_by=data['purchasedBy'],
			items=items_json,
			notes=data.get('notes')
		)

		db.add(new_receipt)
		# commit both the updated grocery items and the new receipt together
		db.commit()
		db.refresh(new_receipt)
		return jsonify(new_receipt.to_dict()), 201
	except Exception as e:
		db.rollback()
		return jsonify({'error': str(e)}), 500
	finally:
		db.close()


@app.route('/api/receipts/<receipt_id>', methods=['PUT'])
def update_receipt(receipt_id):
	"""Update a receipt."""
	data = request.get_json()
	if not data:
		return jsonify({'error': 'No data provided'}), 400

	db = SessionLocal()
	try:
		receipt = db.query(Receipts).filter(Receipts.id == receipt_id).first()
		if not receipt:
			return jsonify({'error': 'Receipt not found'}), 404

		if 'date' in data:
			try:
				receipt.date = datetime.strptime(data['date'], '%Y-%m-%d').date()
			except (ValueError, TypeError):
				return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400
		if 'totalAmount' in data:
			receipt.total_amount = data['totalAmount']
		if 'purchasedBy' in data:
			receipt.purchased_by = data['purchasedBy']
		if 'items' in data:
			receipt.items = json.dumps(data['items']) if isinstance(data['items'], list) else json.dumps([])
		if 'notes' in data:
			receipt.notes = data['notes']

		db.commit()
		db.refresh(receipt)
		return jsonify(receipt.to_dict())
	except Exception as e:
		db.rollback()
		return jsonify({'error': str(e)}), 500
	finally:
		db.close()


@app.route('/api/receipts/<receipt_id>', methods=['DELETE'])
def delete_receipt(receipt_id):
	"""Delete a receipt."""
	db = SessionLocal()
	try:
		receipt = db.query(Receipts).filter(Receipts.id == receipt_id).first()
		if not receipt:
			return jsonify({'error': 'Receipt not found'}), 404

		db.delete(receipt)
		db.commit()
		return jsonify({'message': 'Receipt deleted successfully'})
	except Exception as e:
		db.rollback()
		return jsonify({'error': str(e)}), 500
	finally:
		db.close()

if __name__ == '__main__':
	# Run the Flask development server
	app.run(debug=True, host='0.0.0.0', port=8000)