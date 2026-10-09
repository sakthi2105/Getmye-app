import 'package:flutter/material.dart';

class AcceptPage extends StatelessWidget {
  const AcceptPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Order Accepted")),
      body: Center(child: Text("You accepted the order!")),
    );
  }
}
