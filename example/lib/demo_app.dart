/// A plausible app for the wall to sit on top of.
///
/// The marketing screenshots are taken from this running in a real simulator,
/// so what is behind the wall has to look like a real product — a wall floating
/// over a grey rectangle tells you nothing about how much of an app it covers.
library;

import 'package:flutter/material.dart';

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  'Northwind',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 19,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              height: 132,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF2A2A33), Color(0xFF17171C)],
                ),
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'BALANCE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '\$4,820.15',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+2.4% this month',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'RECENT',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 12),
            ...<List<String>>[
              <String>['Figma', 'Subscription', '-\$15.00'],
              <String>['Transfer', 'To savings', '-\$400.00'],
              <String>['Acme Ltd', 'Invoice #1042', '+\$1,250.00'],
              <String>['Cafe Nero', 'Coffee', '-\$4.20'],
            ].map(
              (List<String> row) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            row[0],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            row[1],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      row[2],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: row[2].startsWith('+')
                            ? const Color(0xFF3ECF8E)
                            : Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
