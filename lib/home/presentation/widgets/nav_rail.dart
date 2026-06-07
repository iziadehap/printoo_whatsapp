// import 'package:flutter/material.dart';
// import '../theme/app_theme.dart';

// class NavRail extends StatefulWidget {
//   const NavRail({super.key});

//   @override
//   State<NavRail> createState() => NavRailState();
// }

// class NavRailState extends State<NavRail> {
//   int _selected = 0;

//   @override
//   Widget build(BuildContext context) {
//     final topIcons = [
//       Icons.home_outlined,
//       Icons.people_outline,
//       Icons.bar_chart_outlined,
//       Icons.info_outline,
//     ];
//     final bottomIcons = [
//       Icons.help_outline,
//       Icons.settings_outlined,
//     ];

//     return Container(
//       width: 46,
//       color: AppColors.bgSidebar,
//       child: Column(
//         children: [
//           const SizedBox(height: 8),
//           ...topIcons.map((icon) => NavIcon(
//                 icon: icon,
//                 selected: _selected == topIcons.indexOf(icon),
//                 onTap: () => setState(() => _selected = topIcons.indexOf(icon)),
//               )),
//           const Spacer(),
//           ...bottomIcons.map((icon) => NavIcon(
//                 icon: icon,
//                 selected: _selected == (topIcons.length + bottomIcons.indexOf(icon)),
//                 onTap: () => setState(() => _selected = topIcons.length + bottomIcons.indexOf(icon)),
//               )),
//           const SizedBox(height: 8),
//         ],
//       ),
//     );
//   }
// }

// class NavIcon extends StatelessWidget {
//   final IconData icon;
//   final bool selected;
//   final VoidCallback onTap;
//   const NavIcon(
//       {required this.icon, required this.selected, required this.onTap, super.key});

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: 40,
//         height: 40,
//         margin: const EdgeInsets.symmetric(vertical: 2),
//         decoration: BoxDecoration(
//           color: selected ? AppColors.bgSelected : Colors.transparent,
//           borderRadius: BorderRadius.circular(8),
//         ),
//         child: Icon(
//           icon,
//           color: selected ? AppColors.accent : AppColors.textMuted,
//           size: 18,
//         ),
//       ),
//     );
//   }
// }
