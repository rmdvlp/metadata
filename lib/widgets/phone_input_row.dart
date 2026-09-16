// import 'package:flutter/material.dart';
// import 'package:metadata/utils/app_colors.dart';
// import 'package:metadata/widgets/custom_text_field.dart';

// class PhoneInputRow extends StatefulWidget {
//   const PhoneInputRow({
//     super.key,
//     required this.controller,
//     this.onCountryCodeChanged,
//   });

//   final TextEditingController controller;
//   final ValueChanged<String>? onCountryCodeChanged;

//   @override
//   State<PhoneInputRow> createState() => _PhoneInputRowState();
// }

// class _PhoneInputRowState extends State<PhoneInputRow> {
//   static const List<_CountryDialCode> _countries = <_CountryDialCode>[
//     _CountryDialCode(name: 'India', flag: '🇮🇳', dialCode: '+91'),
//     _CountryDialCode(name: 'United States', flag: '🇺🇸', dialCode: '+1'),
//     _CountryDialCode(name: 'United Kingdom', flag: '🇬🇧', dialCode: '+44'),
//     _CountryDialCode(name: 'Canada', flag: '🇨🇦', dialCode: '+1'),
//     _CountryDialCode(name: 'Australia', flag: '🇦🇺', dialCode: '+61'),
//     _CountryDialCode(name: 'Germany', flag: '🇩🇪', dialCode: '+49'),
//     _CountryDialCode(name: 'France', flag: '🇫🇷', dialCode: '+33'),
//     _CountryDialCode(name: 'Italy', flag: '🇮🇹', dialCode: '+39'),
//     _CountryDialCode(name: 'Spain', flag: '🇪🇸', dialCode: '+34'),
//     _CountryDialCode(name: 'Netherlands', flag: '🇳🇱', dialCode: '+31'),
//     _CountryDialCode(name: 'Sweden', flag: '🇸🇪', dialCode: '+46'),
//     _CountryDialCode(name: 'Norway', flag: '🇳🇴', dialCode: '+47'),
//     _CountryDialCode(name: 'Denmark', flag: '🇩🇰', dialCode: '+45'),
//     _CountryDialCode(name: 'UAE', flag: '🇦🇪', dialCode: '+971'),
//     _CountryDialCode(name: 'Saudi Arabia', flag: '🇸🇦', dialCode: '+966'),
//     _CountryDialCode(name: 'Singapore', flag: '🇸🇬', dialCode: '+65'),
//     _CountryDialCode(name: 'Malaysia', flag: '🇲🇾', dialCode: '+60'),
//     _CountryDialCode(name: 'Pakistan', flag: '🇵🇰', dialCode: '+92'),
//     _CountryDialCode(name: 'Bangladesh', flag: '🇧🇩', dialCode: '+880'),
//     _CountryDialCode(name: 'Nepal', flag: '🇳🇵', dialCode: '+977'),
//   ];

//   _CountryDialCode _selectedCountry = _countries.first;

//   @override
//   void initState() {
//     super.initState();
//     widget.onCountryCodeChanged?.call(_selectedCountry.dialCode);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Container(
//           height: 56,
//           alignment: Alignment.center,
//           padding: const EdgeInsets.symmetric(horizontal: 12),
//           decoration: BoxDecoration(
//             color: AppColors.white,
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(color: AppColors.border),
//           ),
//           child: DropdownButtonHideUnderline(
//             child: DropdownButton<_CountryDialCode>(
//               value: _selectedCountry,
//               icon: const Icon(
//                 Icons.keyboard_arrow_down_rounded,
//                 color: AppColors.textSecondary,
//                 size: 18,
//               ),
//               dropdownColor: AppColors.white,
//               style: const TextStyle(
//                 color: AppColors.textPrimary,
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//                 fontFamily: 'SF Pro Display',
//               ),
//               items: _countries.map((country) {
//                 return DropdownMenuItem<_CountryDialCode>(
//                   value: country,
//                   child: Text(
//                     '${country.flag} ${country.name} (${country.dialCode})',
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 );
//               }).toList(),
//               selectedItemBuilder: (context) {
//                 return _countries.map((country) {
//                   return Text('${country.flag} ${country.dialCode}');
//                 }).toList();
//               },
//               onChanged: (value) {
//                 if (value != null) {
//                   setState(() {
//                     _selectedCountry = value;
//                   });
//                   widget.onCountryCodeChanged?.call(value.dialCode);
//                 }
//               },
//             ),
//           ),
//         ),
//         const SizedBox(width: 12),
//         Expanded(
//           child: SizedBox(
//             height: 56,
//             child: CustomTextField(
//               controller: widget.controller,
//               hintText: 'Phone number',
//               keyboardType: TextInputType.phone,
//               prefixIcon: const Icon(
//                 Icons.phone_iphone_rounded,
//                 color: AppColors.primaryBlue,
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _CountryDialCode {
//   const _CountryDialCode({
//     required this.name,
//     required this.flag,
//     required this.dialCode,
//   });

//   final String name;
//   final String flag;
//   final String dialCode;
// }

import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/custom_text_field.dart';

class PhoneInputRow extends StatefulWidget {
  const PhoneInputRow({
    super.key,
    required this.controller,
    this.onCountryCodeChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onCountryCodeChanged;

  @override
  State<PhoneInputRow> createState() => _PhoneInputRowState();
}

class _PhoneInputRowState extends State<PhoneInputRow> {
  static const List<_CountryDialCode> _countries = <_CountryDialCode>[
    _CountryDialCode(name: 'United States', flag: '🇺🇸', dialCode: '+1'),
    _CountryDialCode(name: 'South Africa', flag: '🇿🇦', dialCode: '+27'),
    _CountryDialCode(name: 'India', flag: '🇮🇳', dialCode: '+91'),
    _CountryDialCode(name: 'United Kingdom', flag: '🇬🇧', dialCode: '+44'),
    _CountryDialCode(name: 'Canada', flag: '🇨🇦', dialCode: '+1'),
    _CountryDialCode(name: 'Australia', flag: '🇦🇺', dialCode: '+61'),
    _CountryDialCode(name: 'Germany', flag: '🇩🇪', dialCode: '+49'),
    _CountryDialCode(name: 'France', flag: '🇫🇷', dialCode: '+33'),
    _CountryDialCode(name: 'Italy', flag: '🇮🇹', dialCode: '+39'),
    _CountryDialCode(name: 'Spain', flag: '🇪🇸', dialCode: '+34'),
    _CountryDialCode(name: 'Netherlands', flag: '🇳🇱', dialCode: '+31'),
    _CountryDialCode(name: 'Sweden', flag: '🇸🇪', dialCode: '+46'),
    _CountryDialCode(name: 'Norway', flag: '🇳🇴', dialCode: '+47'),
    _CountryDialCode(name: 'Denmark', flag: '🇩🇰', dialCode: '+45'),
    _CountryDialCode(name: 'UAE', flag: '🇦🇪', dialCode: '+971'),
    _CountryDialCode(name: 'Saudi Arabia', flag: '🇸🇦', dialCode: '+966'),
    _CountryDialCode(name: 'Singapore', flag: '🇸🇬', dialCode: '+65'),
    _CountryDialCode(name: 'Malaysia', flag: '🇲🇾', dialCode: '+60'),
    _CountryDialCode(name: 'Pakistan', flag: '🇵🇰', dialCode: '+92'),
    _CountryDialCode(name: 'Bangladesh', flag: '🇧🇩', dialCode: '+880'),
    _CountryDialCode(name: 'Nepal', flag: '🇳🇵', dialCode: '+977'),
  ];

  // Default selection set to US
  _CountryDialCode _selectedCountry = _countries.first;

  @override
  void initState() {
    super.initState();
    widget.onCountryCodeChanged?.call(_selectedCountry.dialCode);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_CountryDialCode>(
              value: _selectedCountry,
              isDense: true,
              alignment: Alignment.center,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              dropdownColor: AppColors.white,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
              items: _countries.map((country) {
                return DropdownMenuItem<_CountryDialCode>(
                  value: country,
                  child: Text(
                    '${country.flag}  ${country.name} (${country.dialCode})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              selectedItemBuilder: (context) {
                return _countries.map((country) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${country.flag} ${country.dialCode}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList();
              },
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCountry = value;
                  });
                  widget.onCountryCodeChanged?.call(value.dialCode);
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 56,
            child: CustomTextField(
              controller: widget.controller,
              hintText: 'Phone number',
              keyboardType: TextInputType.phone,
              prefixIcon: const Icon(
                Icons.phone_iphone_rounded,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryDialCode {
  const _CountryDialCode({
    required this.name,
    required this.flag,
    required this.dialCode,
  });

  final String name;
  final String flag;
  final String dialCode;
}
