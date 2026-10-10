import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(MaterialApp(
    theme: AppTheme.lightTheme,
    home: DeliveryDetailsPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class DeliveryDetailsPage extends StatelessWidget {
  final List<Map<String, String>> deliveries = [
    {
      "name": "Rahul Sharma",
      "food": "Chicken Biryani",
      "budget": "₹250",
      "address": "12, MG Road, Bangalore",
      "time": "12:30 PM"
    },
    {
      "name": "Anita Verma",
      "food": "Paneer Butter Masala",
      "budget": "₹180",
      "address": "56, Lake View St, Delhi",
      "time": "1:00 PM"
    },
    {
      "name": "Vikram Singh",
      "food": "Dosa & Sambar",
      "budget": "₹120",
      "address": "89, Green Park, Mumbai",
      "time": "1:45 PM"
    },
    {
      "name": "Priya Patel",
      "food": "Veg Pulao",
      "budget": "₹150",
      "address": "23, Rajaji St, Chennai",
      "time": "2:15 PM"
    },
    {
      "name": "Rohan Das",
      "food": "Grilled Chicken",
      "budget": "₹350",
      "address": "78, Brigade Rd, Kolkata",
      "time": "3:00 PM"
    },
    {
      "name": "Sanya Mehta",
      "food": "Pasta Alfredo",
      "budget": "₹220",
      "address": "99, Banjara Hills, Hyderabad",
      "time": "3:30 PM"
    },
    {
      "name": "Karthik Reddy",
      "food": "Fish Curry & Rice",
      "budget": "₹280",
      "address": "14, Indira Nagar, Pune",
      "time": "4:00 PM"
    },
    {
      "name": "Neha Kapoor",
      "food": "Momos & Soup",
      "budget": "₹130",
      "address": "30, Whitefield, Bangalore",
      "time": "4:45 PM"
    },
  ];

   DeliveryDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text("Delivery Details", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Column(
            children: deliveries.map((delivery) {
              return SizedBox(
                width: double.infinity, // Makes it full width
                height: 160, // Ensures uniform height
                child: Container(
                  margin: EdgeInsets.all(10),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade300,
                        blurRadius: 5,
                        spreadRadius: 2,
                        offset: Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Customer: ${delivery['name']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 5),
                      Text("Food Item: ${delivery['food']}", style: TextStyle(fontSize: 14)),
                      Text("Budget: ${delivery['budget']}", style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.bold)),
                      Text("Address: ${delivery['address']}", style: TextStyle(fontSize: 14)),
                      Text("Delivery Time: ${delivery['time']}", style: TextStyle(fontSize: 14, color: Colors.red)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}