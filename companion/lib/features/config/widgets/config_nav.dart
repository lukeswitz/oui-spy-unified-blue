import 'package:flutter/material.dart';

class ConfigSection {
  const ConfigSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

const kConfigSections = <ConfigSection>[
  ConfigSection('APP', Icons.tune),
  ConfigSection('SCANNING', Icons.radar),
  ConfigSection('DETECTION', Icons.notifications_active),
  ConfigSection('NODE', Icons.memory),
  ConfigSection('DATA', Icons.storage),
];
