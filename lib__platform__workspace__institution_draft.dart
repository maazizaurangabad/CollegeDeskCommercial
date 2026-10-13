import 'package:flutter/material.dart';

import '../academic/structure_templates.dart';

/// What the setup wizard collects before an institution is created.
class InstitutionDraft {
  InstitutionDraft({
    this.name = '',
    this.shortName = '',
    this.institutionType = 'Junior college',
    this.city = '',
    this.state = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.udiseCode = '',
    this.board = '',
    this.medium = '',
    required this.yearLabel,
    required this.yearStart,
    required this.yearEnd,
    this.template = StructureTemplate.juniorCollege,
    required this.brandColor,
    this.logoSourcePath,
  });

  String name;
  String shortName;
  String institutionType;
  String city;
  String state;
  String address;
  String phone;
  String email;
  String website;
  String udiseCode;
  String board;
  String medium;
  String yearLabel;
  DateTime yearStart;
  DateTime yearEnd;
  StructureTemplate template;
  Color brandColor;

  /// Picked logo image; copied into the institution's own folder on creation.
  String? logoSourcePath;

  /// Indian academic years start in June: from June 2026 the default is 2026-27.
  static ({String label, DateTime start, DateTime end}) defaultYear(DateTime today) {
    final first = today.month >= 6 ? today.year : today.year - 1;
    final second = (first + 1) % 100;
    return (
      label: '$first-${second.toString().padLeft(2, '0')}',
      start: DateTime(first, 6, 1),
      end: DateTime(first + 1, 4, 30),
    );
  }
}
