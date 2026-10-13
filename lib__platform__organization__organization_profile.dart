import 'package:flutter/material.dart';

/// The institution using the app. Everything institution-specific
/// (name, branding, labels) comes from here, never from code.
@immutable
class OrganizationProfile {
  const OrganizationProfile({
    required this.id,
    required this.name,
    required this.shortName,
    required this.institutionType,
    required this.city,
    required this.activeAcademicYear,
    required this.brandColor,
    this.address,
    this.state,
    this.phone,
    this.email,
    this.website,
    this.board,
    this.medium,
    this.udiseCode,
    this.logoFileName,
    this.programLabel,
    this.divisionLabel,
  });

  final String id;
  final String name;
  final String shortName;
  final String institutionType;
  final String city;
  final String activeAcademicYear;
  final Color brandColor;
  final String? address;
  final String? state;
  final String? phone;
  final String? email;
  final String? website;
  final String? board;
  final String? medium;
  final String? udiseCode;
  final String? logoFileName;
  final String? programLabel;
  final String? divisionLabel;

  /// Up to two letters for the monogram, e.g. "Greenfield College" -> "GC".
  String get initials {
    final words = shortName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  OrganizationProfile copyWith({
    String? name,
    String? shortName,
    String? institutionType,
    String? city,
    String? activeAcademicYear,
    Color? brandColor,
    String? address,
    String? state,
    String? phone,
    String? email,
    String? website,
    String? board,
    String? medium,
    String? udiseCode,
    String? logoFileName,
    String? programLabel,
    String? divisionLabel,
  }) {
    return OrganizationProfile(
      id: id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      institutionType: institutionType ?? this.institutionType,
      city: city ?? this.city,
      activeAcademicYear: activeAcademicYear ?? this.activeAcademicYear,
      brandColor: brandColor ?? this.brandColor,
      address: address ?? this.address,
      state: state ?? this.state,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      board: board ?? this.board,
      medium: medium ?? this.medium,
      udiseCode: udiseCode ?? this.udiseCode,
      logoFileName: logoFileName ?? this.logoFileName,
      programLabel: programLabel ?? this.programLabel,
      divisionLabel: divisionLabel ?? this.divisionLabel,
    );
  }

  Map<String, Object?> toAuditMap() => {
        'name': name,
        'short_name': shortName,
        'institution_type': institutionType,
        'city': city,
        'active_academic_year': activeAcademicYear,
        'brand_color': brandColor.toARGB32(),
        'address': address,
        'state': state,
        'phone': phone,
        'email': email,
        'website': website,
        'board': board,
        'medium': medium,
        'udise_code': udiseCode,
        'logo_file_name': logoFileName,
        'program_label': programLabel,
        'division_label': divisionLabel,
      };
}
