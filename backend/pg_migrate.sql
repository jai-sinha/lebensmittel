-- PostgreSQL migration script

BEGIN;

CREATE TABLE grocery_items (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    is_needed BOOLEAN NOT NULL,
    is_shopping_checked BOOLEAN NOT NULL
);

INSERT INTO grocery_items VALUES
('4532fc0c-1502-4d31-b2a7-143f77d248f5','Bananas','Essentials',FALSE,FALSE),
('58b88630-b288-4f9c-a68c-67e95187c05c','Lemons','Essentials',FALSE,FALSE),
('58213160-8ad0-4b38-bb44-e8b94e9d12d0','Limes','Essentials',FALSE,FALSE),
('07e8ffc9-6e55-4ba4-93ab-e474ad5cec5e','Frozen fruit','Essentials',FALSE,FALSE),
('5d02e480-fba9-479e-8eb7-1267d84bd02f','Milk','Essentials',FALSE,FALSE),
('b64ab0bc-e4f0-44d1-8236-3cef59e63e5b','Juice','Essentials',FALSE,FALSE),
('4cb707bb-4107-46cb-8998-38eadb2f8d06','Eggs','Essentials',FALSE,FALSE),
('baee7c88-8470-4591-9028-0607c4026a53','Cilantro','Essentials',FALSE,FALSE),
('e2bcd4c0-2b6a-406e-a5ee-1b2cb865b8f1','Apple cider v','Other',FALSE,FALSE),
('3f042c5b-fb62-4a6e-b377-dee160d2763d','Spaghetti','Essentials',FALSE,FALSE),
('e2078656-af38-4bf9-ab96-d2bb02a4b3f5','Tomatoes','Essentials',FALSE,FALSE),
('62ed67bc-0456-4e23-9504-9adbe52b53b4','Avocados','Essentials',FALSE,FALSE),
('cc35ad37-0ffa-4675-bcf0-b9e5876c2236','Olive oil','Other',FALSE,FALSE),
('789880b6-7c88-4052-807a-e98d360c62f6','Yogurt','Essentials',FALSE,FALSE),
('c980dfef-28c6-41f7-89bf-dcd66e92d1e6','Chicken thighs','Protein',FALSE,FALSE),
('11ab3b44-748f-461f-93a8-1808580b0915','Chicken breasts','Protein',FALSE,FALSE),
('2853cd71-7caf-4e86-9c66-bdb36b1c40ea','Tuna','Essentials',FALSE,FALSE),
('d8ae6e8e-7069-4b2f-a5d4-95b1618d05b9','Red onion','Veggies',FALSE,FALSE),
('f820247d-0115-4899-9384-f34e7e46327d','Pickles','Veggies',FALSE,FALSE),
('d2baae1b-c125-447a-9171-00d969543dcb','Leafy greens','Veggies',FALSE,FALSE),
('70701953-fcc2-4c44-a8e5-bb2a58969c1a','Paper towels','Household',FALSE,FALSE),
('53e5422b-a8ed-4e70-9096-a9c94bbea8a8','Dish soap','Household',FALSE,FALSE),
('2e582086-9622-49a1-86eb-220cedb2f3c3','Parmesan','Carbs',FALSE,FALSE),
('9667370d-5203-4b0f-81b4-113cffcbafba','Coffee beans','Other',FALSE,FALSE),
('94908112-c552-4046-9968-652948667c7e','Buns','Carbs',FALSE,FALSE),
('c1c37f6e-af9c-4840-b18a-85a1ea40ad70','Tortillas','Carbs',FALSE,FALSE),
('34af1f58-c065-486b-9dbe-23038fbcd79b','Jasmine rice','Carbs',FALSE,FALSE),
('e2056283-87b7-4aa1-b97d-2dfd42e198ca','Mirin','Other',FALSE,FALSE),
('a880fafe-fc4c-43c1-a086-7b70452c23c6','Beer','Essentials',FALSE,FALSE),
('cfa3bdef-f5ef-43cc-b02b-43898e7e666f','Whitefish','Protein',FALSE,FALSE),
('ae541496-fcb0-461b-a895-4efd8df4a0f1','Salmon','Protein',FALSE,FALSE),
('80e50f7f-7e6d-4c8c-a444-d60005e5141f','Sliced cheese','Essentials',FALSE,FALSE),
('04fa2d71-8d4b-46d4-aaf6-50322e97b660','Sliced bread','Essentials',FALSE,FALSE),
('9b76dd2e-bab3-476d-b286-28c735430a80','Cereal / müsli','Essentials',FALSE,FALSE),
('84d651d4-9b7a-47ae-a12a-2cf9cc0e4518','Turkey','Essentials',FALSE,FALSE),
('7cd216eb-55dc-409e-8251-7147e511b5e9','Ground beef','Protein',FALSE,FALSE),
('448923cc-7232-4d02-8b9d-043b55052edb','Wurst','Protein',FALSE,FALSE),
('bec078f1-e46e-4610-9597-b7c8da084bbe','Frozen pizza','Essentials',FALSE,FALSE),
('adbdce2b-006b-4808-b3d4-158331de1e01','Mayo','Other',FALSE,FALSE),
('c9e751b4-2d13-4304-82e3-30975db4b01b','Toilet paper','Household',FALSE,FALSE),
('76b3f690-8aa5-48b2-8466-932efccf5f11','White onion','Veggies',FALSE,FALSE),
('4f11e35f-88a7-4a95-981a-f1504d2592d4','Cabbage','Veggies',FALSE,FALSE),
('a360ad45-0f2a-461d-96b5-340407be5f5f','Dishwasher pods','Household',FALSE,FALSE),
('b3fc0f86-19b1-42d4-906c-9f7874b2f217','Tofu','Protein',FALSE,FALSE),
('410816ef-d50b-439b-af28-b7de4ababb41','Pork','Protein',FALSE,FALSE),
('6a53990a-169c-4cb5-a4e6-a9174582879a','Rice vinegar','Other',FALSE,FALSE),
('31e6bd19-7756-4645-b7db-a2e4dae7bee3','Garlic','Other',FALSE,FALSE);

CREATE TABLE meal_plans (
    id UUID PRIMARY KEY,
    date DATE NOT NULL,
    meal_description TEXT NOT NULL
);

INSERT INTO meal_plans VALUES
('eec372e1-b32d-44c2-9cf9-dc06a1c0d118','2025-10-30','Harissa tacos'),
('b85a9bad-8e87-4ef1-9c8f-24781cc1fd4e','2025-10-28','Chicken sandwiches'),
('3078da62-f2b1-40e2-b665-307dbf3cff40','2025-10-29','Katsu'),
('69ed7718-9cfa-465f-a938-900bef782a04','2025-10-31','Carbonara'),
('24f70fa9-5a3a-46f2-9abb-f24f84f0e4ce','2025-11-02','Creamy salmon and rice'),
('cffee64a-9915-4186-b2a1-686136d07087','2025-11-01','Biryani'),
('d9c66255-df90-4232-a7c0-fd264b14a6c1','2025-11-05','Butter chicken'),
('35dd1ecb-98d1-4d76-98a5-7cca26cbf143','2025-11-06','Tofu n rice thai style'),
('1629b10f-2c3e-4c55-b9b3-f315e12c0da7','2025-11-04','Pizza'),
('2e0d56d3-8150-48df-bebb-649a09a97018','2025-11-03','Chicken n pasta'),
('fb0a2e21-75c6-4132-9d65-5c43b9ecde0b','2025-11-07','Paninis'),
('4f23bc69-ac29-4c01-a7e4-64d7bdcc39aa','2025-11-08','Fish tacos'),
('5ac4d2f0-f8f8-42fe-a0c5-227aa29ec9d3','2025-11-09','Shawarma'),
('e87b9a4b-8046-477e-b68b-6c2b919420e4','2025-11-12','Biryani'),
('f33e0c4b-fe48-4bbb-9b08-6b7b9575f466','2025-11-11','Frozen za'),
('49d93485-a04e-467c-8c6b-c89c5c7c62f0','2025-11-10','I dont remember'),
('2208c602-95fd-462a-814c-1fdaceb97138','2025-11-16','Harissa tacos'),
('9a411592-a205-48b8-94f3-1142b3fdf275','2025-11-15','Frozen pizza'),
('d0eb2872-7f17-4bc6-9170-e4d3bbebc25e','2025-11-13','Jai by himself'),
('d4c7fb4a-8616-4a55-b9e1-e44e59cf3f0b','2025-11-14','Pasta and sausage'),
('0265aa19-8077-41f3-8b48-1d3a37de6977','2025-11-17','Salmon hanna style'),
('02e0a838-93da-4b7e-9d52-d86e6a0b8aed','2025-11-18','Chicken adobo'),
('388a5687-35a2-4cd9-9402-75ca7a171659','2025-11-19','Soy beef and noodles stir fry'),
('60969708-ff7e-4ab3-8347-d8cbbfca2f71','2025-11-20','Frozen za'),
('469b40b7-f254-40fc-ba1a-e4e0682400f9','2025-11-21','Spaghetti sausage'),
('0ec52974-dcae-4ff6-9a4c-2a57b9b59b4b','2025-11-22','Tenmaya res'),
('e6a738da-b8df-457d-ab1a-70a64508975c','2025-11-23','Katsu'),
('5de4abc6-2d24-4b19-9566-baef87873fa6','2025-11-24','Biryani'),
('7db81d18-24a6-46cd-bbf8-3ce7f4ba1d69','2025-11-25','Max Pett @6'),
('1d98b756-f46c-4fc5-98cb-56933e12edf3','2025-11-29','Frozen pizza'),
('98c42df8-7d05-4b03-9266-104ae0bc27cb','2025-11-28','Chicken sandwiches'),
('3706e245-2e5f-4969-8ea6-eb5fd7a53850','2025-11-30','Butter chicken'),
('186a38bd-6381-4982-9811-ae5ca3bf9add','2025-12-01','Harissa tacos'),
('412ebb7c-9d7f-4529-8cfb-c49702393649','2025-12-02','Coq au vin'),
('ae93fc8b-1745-45f8-a8af-1918b7a7788e','2025-12-03','Creamy salmon'),
('74cf7238-7a2b-45d9-b62b-1a7d0df04702','2025-12-04','Adobo'),
('ebd254c8-0392-4a8e-8a74-2068668d831b','2025-12-05','Firecracker pork'),
('df2f6231-3efb-4fd2-969d-c382cbafceaf','2025-12-06','Sardine spaghetti'),
('2509e4d4-3f49-4c4c-bdba-c6ed2440a700','2025-12-07','Dhruv housewarming pizza');

CREATE TABLE receipts (
    id UUID PRIMARY KEY,
    date DATE NOT NULL,
    total_amount FLOAT NOT NULL,
    purchased_by VARCHAR(50) NOT NULL,
    items TEXT,
    notes TEXT
);

INSERT INTO receipts VALUES
('6541e9a1-c95b-4106-881f-fbcdd3c5a702','2025-10-30',42.0,'Jai','["Milk", "Juice", "Eggs", "Turkey", "Cilantro", "Apple cider v", "Pepperoni", "Shredded mozzarella", "Parmesan", "Bacon", "Parsley", "Tomatoes", "Avocados"]','For some reason this wouldnt connect at netto hmm'),
('ca604e90-56dd-4591-9288-57847b76a0fc','2025-10-31',22.5,'Hanna','["Rewe lunch and netto 31.10"]',''),
('46e4c699-7891-4b08-8965-b23fc02b81d0','2025-11-03',36.79999999999999715,'Jai','["Lemons", "Milk", "Juice", "Eggs", "Any green and leafy", "Parmesan", "Avocados", "Coffee beans", "Paper towels", "Dish soap", "Chicken thighs", "Chicken breasts", "Carrots"]',''),
('b0581abd-bf04-4953-b1b9-0c06f0811a32','2025-11-05',41.4200000000000017,'Hanna','["Bananas", "Milk", "Juice", "Yogurt", "Tuna", "Pickles", "Leafy greens", "Coffee beans", "Sliced bread"]',''),
('ba1bd8c6-58a0-400e-a451-d1cedcc578d4','2025-11-07',26.0,'Jai','["Tomatoes", "Avocados", "Tortillas", "Whitefish", "Naan"]',''),
('0937f47e-2193-4df2-8f76-55e301b3bbb9','2025-11-08',48.81000000000000227,'Hanna','["Milk", "Eggs", "Cilantro", "Chicken thighs", "Leafy greens", "Sliced bread", "Beer", "Sliced cheese"]',''),
('89be00e2-a51c-40d2-b33c-763f3511cff3','2025-11-12',43.0,'Hanna','["Bananas", "Frozen fruit", "Milk", "Juice", "Tomatoes", "Chicken thighs", "Cereal / m\u00fcsli"]','And some other stuff'),
('76b77b8c-fa1f-435a-b67c-af9671cb64c2','2025-11-14',18.28999999999999915,'Jai','["Bananas", "Lemons", "Milk", "Apple cider v", "Yogurt", "Chicken breasts"]',''),
('d6e63874-18d4-4526-9a77-a0c4d3922d54','2025-11-17',42.72999999999999687,'Jai','["Bananas", "Milk", "Juice", "Spaghetti", "Tomatoes", "Leafy greens", "Jasmine rice", "Salmon", "Turkey", "Ground beef", "Wurst"]',''),
('a3fceeda-11ea-4208-9b7c-56cd7eeb1626','2025-11-19',27.0,'Hanna','["Milk", "Juice", "Cilantro", "Leafy greens", "Turkey", "Toilet paper"]',''),
('a32fca9e-5d75-4195-a240-d616d54a5aed','2025-11-21',32.38000000000000255,'Jai','["Bananas", "Milk", "Eggs", "Avocados", "Chicken breasts", "Parmesan", "Frozen pizza", "Cabbage"]',''),
('bcff7c35-ea22-4953-a8cf-e38d5aa1102a','2025-11-24',0.0100000000000000002,'Jai','["Bananas", "Limes", "Frozen fruit", "Juice", "Cilantro", "Olive oil", "Chicken thighs", "Jasmine rice", "Sliced bread", "Frozen pizza", "Dishwasher pods", "Tofu"]','Apple cardddd 78 euros'),
('18a738f2-f77e-44eb-98fd-d29c45d868dd','2025-11-27',0.0100000000000000002,'Jai','["Yogurt", "Pickles", "Coffee beans", "Sliced cheese", "Pork"]','Apple carddd'),
('c4ba6dd9-841f-4bc3-88f9-46e5b3c7ab3f','2025-11-28',24.0,'Jai','["Eggs", "Chicken thighs", "Chicken breasts"]',''),
('3b1f6a89-2e03-4c2a-9dd7-c1993b5dec4d','2025-11-28',15.0,'Hanna','["Buns"]',''),
('f0eed3cb-836d-49bb-af09-6baf2d235601','2025-12-02',38.5,'Jai','["Bananas", "Lemons", "Milk", "Juice", "Chicken breasts", "Tuna", "Leafy greens", "Tortillas", "Salmon", "Sliced bread", "Turkey"]',''),
('3162769a-9551-4536-8956-953e860b4fb0','2025-12-03',40.0,'Hanna','["Bananas", "Spaghetti", "Tomatoes", "Chicken thighs", "Tuna", "Turkey", "Pork"]',''),
('a0629679-9c03-45c3-8bff-3a9b8a903cf4','2025-12-04',16.0,'Hanna','["Frozen fruit", "Juice", "Garlic"]',''),
('b4b4667f-73ca-487e-9534-ff20ad5bd3d9','2025-12-07',16.0,'Jai','["Bananas", "Milk", "Avocados", "Sliced bread"]',''),
('26a3cc7c-1679-4853-8bd6-01c28b709d1a','2025-12-08',39.0,'Hanna','["Bananas"]','Netto');

COMMIT;

-- End of migration script
-- run with: psql -U jsinha -d lebensmittel -f pg_migrate.sql
