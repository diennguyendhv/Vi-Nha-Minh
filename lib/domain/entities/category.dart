import 'package:flutter/material.dart';

import 'transaction_type.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.type,
    this.isDefault = true,
  });

  final String id;
  final String name;
  final Color color;
  final TransactionType type;
  final bool isDefault;

  String get initial => name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
}
