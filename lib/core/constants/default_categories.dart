import 'package:flutter/material.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/transaction_type.dart';

class DefaultCategories {
  DefaultCategories._();

  static const expense = <Category>[
    Category(
      id: 'sinhhoat',
      name: 'Sinh hoạt',
      color: Color(0xFF3E6FB0),
      type: TransactionType.expense,
    ),
    Category(
      id: 'anuong',
      name: 'Ăn uống',
      color: Color(0xFFC98A3E),
      type: TransactionType.expense,
    ),
    Category(
      id: 'dichuyen',
      name: 'Di chuyển',
      color: Color(0xFF8A4FB0),
      type: TransactionType.expense,
    ),
    Category(
      id: 'tuthuong',
      name: 'Tự thưởng',
      color: Color(0xFFC14F7A),
      type: TransactionType.expense,
    ),
    Category(
      id: 'danghien',
      name: 'Dâng hiến',
      color: Color(0xFF2F6F5C),
      type: TransactionType.expense,
    ),
    Category(
      id: 'chodi',
      name: 'Cho đi',
      color: Color(0xFF3E86B0),
      type: TransactionType.expense,
    ),
  ];

  static const income = <Category>[
    Category(
      id: 'luong',
      name: 'Lương',
      color: Color(0xFF2F8F4F),
      type: TransactionType.income,
    ),
    Category(
      id: 'thuong',
      name: 'Thưởng',
      color: Color(0xFF8FA13E),
      type: TransactionType.income,
    ),
    Category(
      id: 'khac',
      name: 'Thu khác',
      color: Color(0xFF6B6F76),
      type: TransactionType.income,
    ),
  ];

  static const quickNotes = <String>['Chợ', 'Xăng xe', 'Cà phê', 'Hoá đơn', 'Khác'];

  static List<Category> get all => [...expense, ...income];

  static Category byId(String id) {
    return all.firstWhere(
      (c) => c.id == id,
      orElse: () => const Category(
        id: '',
        name: '',
        color: Color(0xFF9A9D97),
        type: TransactionType.expense,
      ),
    );
  }
}
