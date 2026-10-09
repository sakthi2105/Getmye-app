import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FoodComboPage(),
  ));
}

class FoodComboPage extends StatelessWidget {
  final List<Map<String, String>> foodCombos = [
    {"name": "Chicken Biryani", "image": "https://www.themealdb.com/images/media/meals/xxyupu1468262513.jpg", "price": "₹250"},
    {"name": "Paneer Butter Masala", "image": "https://www.themealdb.com/images/media/meals/58oia61564916529.jpg", "price": "₹220"},
    {"name": "Mutton Rogan Josh", "image": "https://www.themealdb.com/images/media/meals/vvpprx1487325699.jpg", "price": "₹350"},
    {"name": "Veg Thali", "image": "https://www.themealdb.com/images/media/meals/utxqpt1511639216.jpg", "price": "₹180"},
    {"name": "Chicken 65", "image": "https://www.themealdb.com/images/media/meals/qptpvt1487339892.jpg", "price": "₹270"},
    {"name": "Dosa with Sambar", "image": "https://www.themealdb.com/images/media/meals/tvtxpq1511464705.jpg", "price": "₹120"},
    {"name": "Fish Curry", "image": "https://www.themealdb.com/images/media/meals/uvuyxu1503067369.jpg", "price": "₹300"},
    {"name": "Chole Bhature", "image": "https://www.themealdb.com/images/media/meals/yxsurp1511304301.jpg", "price": "₹150"},
    {"name": "Tandoori Chicken", "image": "https://www.themealdb.com/images/media/meals/58oia61564916529.jpg", "price": "₹320"},
    {"name": "Rajma Chawal", "image": "https://www.themealdb.com/images/media/meals/uuxwvq1483907861.jpg", "price": "₹160"},
    {"name": "Prawn Masala", "image": "https://www.themealdb.com/images/media/meals/xxyupu1468262513.jpg", "price": "₹380"},
    {"name": "Aloo Paratha", "image": "https://www.themealdb.com/images/media/meals/sywswr1511383814.jpg", "price": "₹140"},
    {"name": "Egg Curry", "image": "https://www.themealdb.com/images/media/meals/utxqpt1511639216.jpg", "price": "₹190"},
    {"name": "Kadhai Paneer", "image": "https://www.themealdb.com/images/media/meals/wtsvxx1511296896.jpg", "price": "₹210"},
    {"name": "Hyderabadi Mutton Biryani", "image": "https://www.themealdb.com/images/media/meals/xxtsvx1511814083.jpg", "price": "₹400"},
    {"name": "Chilli Chicken", "image": "https://www.themealdb.com/images/media/meals/1520084413.jpg", "price": "₹290"},
    {"name": "Dal Makhani", "image": "https://www.themealdb.com/images/media/meals/utxqpt1511639216.jpg", "price": "₹200"},
    {"name": "Pasta Alfredo", "image": "https://www.themealdb.com/images/media/meals/uvuyxu1503067369.jpg", "price": "₹180"},
    {"name": "Butter Naan & Paneer Tikka", "image": "https://www.themealdb.com/images/media/meals/qptpvt1487339892.jpg", "price": "₹250"},
    {"name": "Gulab Jamun", "image": "https://www.themealdb.com/images/media/meals/uvuyxu1503067369.jpg", "price": "₹100"},
    {"name": "Rasgulla", "image": "https://www.themealdb.com/images/media/meals/wxuvuv1511783529.jpg", "price": "₹120"},
    {"name": "Ice Cream Sundae", "image": "https://www.themealdb.com/images/media/meals/xsxxqy1511638381.jpg", "price": "₹150"},
    {"name": "Chocolate Cake", "image": "https://www.themealdb.com/images/media/meals/ryppsv1511818353.jpg", "price": "₹200"},
    {"name": "Mango Lassi", "image": "https://www.themealdb.com/images/media/meals/yqwtvu1511815045.jpg", "price": "₹90"},
    {"name": "Fruit Salad", "image": "https://www.themealdb.com/images/media/meals/txsupu1511813850.jpg", "price": "₹130"},
    {"name": "Brownie with Ice Cream", "image": "https://www.themealdb.com/images/media/meals/tvswqs1511791600.jpg", "price": "₹220"},
    {"name": "Kheer", "image": "https://www.themealdb.com/images/media/meals/vtxyxv1511815477.jpg", "price": "₹110"},
    {"name": "Shahi Tukda", "image": "https://www.themealdb.com/images/media/meals/1520084585.jpg", "price": "₹140"},
    {"name": "Jalebi", "image": "https://www.themealdb.com/images/media/meals/yvpxqy1511636542.jpg", "price": "₹80"},
  ];

  FoodComboPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text("Food Combos", style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF17211B))),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF17211B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.72,
        ),
        itemCount: foodCombos.length,
        itemBuilder: (context, index) {
          final food = foodCombos[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5EAE6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                  child: AspectRatio(
                    aspectRatio: 1.35,
                    child: Image.network(
                      food["image"]!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food["name"]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF17211B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        food["price"]!,
                        style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => OrderDetailsPage(foodName: food["name"]!)),
                            );
                          },
                          child: const Text("Order Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class OrderDetailsPage extends StatelessWidget {
  final String foodName;
  const OrderDetailsPage({super.key, required this.foodName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text("Order Details", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF17211B))),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF17211B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 60, color: Color(0xFF15803D)),
              ),
              const SizedBox(height: 20),
              Text(
                "$foodName Ordered Successfully!",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF17211B)),
              ),
              const SizedBox(height: 10),
              const Text(
                "Your order has been sent to the kitchen and will be delivered shortly.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B756D), fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Back to Menu", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}