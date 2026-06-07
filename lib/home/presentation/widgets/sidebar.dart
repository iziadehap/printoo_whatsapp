import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../domain/entities/customer.dart';
import '../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => SidebarState();
}

class SidebarState extends ConsumerState<Sidebar> {
  final _searchCtrl = TextEditingController();

  // Holds the exact suffix text display (e.g., "1d", "2d", "99d")
  String _timeDisplay = '1d';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void selectAndFetchMedia(Customer customer) {
    final days = int.parse(_timeDisplay.replaceAll('d', ''));

    ref.read(selectedCustomerProvider.notifier).state = customer;
    ref.read(mediaProvider.notifier).fetch(customer.id, days);
  }

  // Intercept text input to catch * followed by any digits (e.g., *1, *2, *99)
  void handleSearchInput(String rawValue) {
    String cleanValue = rawValue;
    String updatedDisplay = _timeDisplay;

    // RegEx matches an asterisk followed by one or more digits
    final regExp = RegExp(r'\*(\d+)');
    final match = regExp.firstMatch(rawValue);

    if (match != null) {
      // Extract the number digits from the first capture group
      final String? digits = match.group(1);
      if (digits != null) {
        updatedDisplay = '${digits}d';
        // Strip the entire pattern (e.g., "*99") out of the text
        cleanValue = rawValue.replaceAll(regExp, '');
      }
    }

    // Safely update input text configuration without disrupting cursor index
    if (cleanValue != rawValue) {
      _searchCtrl.value = TextEditingValue(
        text: cleanValue,
        selection: TextSelection.collapsed(offset: cleanValue.length),
      );
    }

    if (updatedDisplay != _timeDisplay) {
      setState(() {
        _timeDisplay = updatedDisplay;
      });
    }

    // Run the search query with the updated text and extracted duration code
    onSearchChanged(cleanValue, _timeDisplay);
  }

  void onSearchChanged(String value, String time) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Passes clean value and extracted value (e.g. "99d") directly to backend
      ref.read(searchProvider.notifier).search(value);
    });
  }

  // Manual click handler: defaults back to toggling cleanly between 1d and 2d
  void _toggleTimeFilter() {
    setState(() {
      _timeDisplay = (_timeDisplay == '1d') ? '2d' : '1d';
    });
    onSearchChanged(_searchCtrl.text, _timeDisplay);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(statusProvider);
    final searchState = ref.watch(searchProvider);
    final selected = ref.watch(selectedCustomerProvider);

    return Container(
      width: 280,
      color: AppColors.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // QR / Status Area
          if (!status.whatsappConnected && status.qrCode != null)
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: status.qrCode!,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),

          // Search Field
          SidebarSection(
            label: 'SEARCH CUSTOMER',
            child: TextField(
              controller: _searchCtrl,
              onChanged: handleSearchInput,
              decoration: InputDecoration(
                hintText: 'Enter Number/Name',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textMuted,
                  size: 16,
                ),
                // Dynamic suffix container matching any digit string argument given
                suffixIcon: InkWell(
                  onTap: _toggleTimeFilter,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    width:
                        44, // Slightly widened to safely fit 3+ digit targets like "120d"
                    child: Text(
                      _timeDisplay,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),

          // Customer List Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Text(
              _searchCtrl.text.isEmpty ? 'RECENT CUSTOMERS' : 'RESULTS',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),

          // Results Stream/State List UI Builder
          Expanded(
            child: searchState.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  e.toString(),
                  style: const TextStyle(color: AppColors.red, fontSize: 11),
                ),
              ),
              data: (customers) {
                if (customers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchCtrl.text.isEmpty
                            ? 'Type to search customers'
                            : 'No results found',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: customers.length,
                  itemBuilder: (_, i) {
                    final c = customers[i];
                    final isSelected = selected?.id == c.id;
                    return CustomerTile(
                      customer: c,
                      isSelected: isSelected,
                      searchQuery: _searchCtrl.text,
                      onTap: () {
                        selectAndFetchMedia(c);
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Bottom Action Button Block
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      ref.read(searchProvider.notifier).search('');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text(
                      'Clear (Ctrl+x)',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SidebarSection extends StatelessWidget {
  final String label;
  final Widget child;
  const SidebarSection({required this.label, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class CustomerTile extends StatelessWidget {
  final Customer customer;
  final bool isSelected;
  final String searchQuery;
  final VoidCallback onTap;

  const CustomerTile({
    required this.customer,
    required this.isSelected,
    required this.searchQuery,
    required this.onTap,
    super.key,
  });

  Widget _buildHighlightedText(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty || !text.contains(query)) {
      return Text(text, style: baseStyle);
    }

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = text.indexOf(query, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }

      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: const TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.bgSelected : AppColors.bgSidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withOpacity(0.5)
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    customer.name.isEmpty ? customer.number : customer.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    customer.relativeTime,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildHighlightedText(
                    customer.number,
                    searchQuery,
                    const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 12,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    "ID: ${customer.id.substring(0, indexOrLength(customer.id))}",
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int indexOrLength(String id) => id.length > 8 ? 8 : id.length;
}
