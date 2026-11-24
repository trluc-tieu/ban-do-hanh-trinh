import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/province_stats.dart';
import '../providers/trip_provider.dart';
import '../services/companion_quotes.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class ProvinceRankingScreen extends StatefulWidget {
  const ProvinceRankingScreen({super.key});

  @override
  State<ProvinceRankingScreen> createState() => _ProvinceRankingScreenState();
}

class _ProvinceRankingScreenState extends State<ProvinceRankingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'Khám Phá Toàn Diện':
        return const Color(0xFF10B981); // Emerald
      case 'Khám Phá Sâu':
        return const Color(0xFF06B6D4); // Cyan
      case 'Đã Ghé Thăm':
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  Widget _buildMedal(int rank) {
    if (rank == 1) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFFFD700),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.amber, blurRadius: 6)],
        ),
        child: const Center(
          child: Text('🥇', style: TextStyle(fontSize: 16)),
        ),
      );
    } else if (rank == 2) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFE0E0E0),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🥈', style: TextStyle(fontSize: 16)),
        ),
      );
    } else if (rank == 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFCD7F32),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🥉', style: TextStyle(fontSize: 16)),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$rank',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final allRankings = tripProvider.getProvinceRankings();
    final exploredCount = tripProvider.exploredProvinceCount;
    final totalKm = tripProvider.totalExploredKm;
    final progress = exploredCount / 63.0;

    final exploredList = allRankings.where((p) => p.distanceKm > 0 || p.traveledKm > 0 || p.tripCount > 0).toList();
    final unvisitedList = allRankings.where((p) => p.distanceKm == 0 && p.traveledKm == 0 && p.tripCount == 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khám phá 63 Tỉnh/Thành'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primary,
          tabs: [
            Tab(text: 'Đã đến ($exploredCount)'),
            const Tab(text: 'Tất cả (63)'),
            Tab(text: 'Chưa đến (${63 - exploredCount})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header summary card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.public, color: AppTheme.discoveryNeon, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'BẢN ĐỒ VIỆT NAM CÁ NHÂN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary, width: 0.8),
                      ),
                      child: Text(
                        '${(progress * 100).toStringAsFixed(1)}% HOÀN THÀNH',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '$exploredCount / 63 Tỉnh / Thành phố',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.discoveryNeon),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tổng tích lũy: ${totalKm.toStringAsFixed(1)} km',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      'Còn ${63 - exploredCount} tỉnh cần chinh phục',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: AppTheme.discoveryNeon, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          CompanionQuotes.pickProvinceSummaryQuote(
                            exploredCount: exploredCount,
                            ranked: allRankings,
                            trips: tripProvider.trips,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tỉnh / thành phố...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim().toLowerCase());
              },
            ),
          ),
          const SizedBox(height: 8),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProvinceList(exploredList),
                _buildProvinceList(allRankings),
                _buildProvinceList(unvisitedList, isUnvisited: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProvinceList(List<ProvinceStats> sourceList, {bool isUnvisited = false}) {
    final list = _searchQuery.isEmpty
        ? sourceList
        : sourceList.where((p) => p.provinceName.toLowerCase().contains(_searchQuery)).toList();

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_outlined, size: 50, color: Colors.grey.withOpacity(0.5)),
              const SizedBox(height: 12),
              Text(
                isUnvisited ? 'Tuyệt vời! Bạn đã khám phá toàn bộ các tỉnh thành!' : 'Chưa có tỉnh thành nào phù hợp',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final p = list[index];
        final isExplored = p.distanceKm > 0 || p.traveledKm > 0 || p.tripCount > 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _buildMedal(p.rank),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.provinceName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isExplored) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _tierColor(p.tierName).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _tierColor(p.tierName), width: 0.8),
                              ),
                              child: Text(
                                p.tierName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _tierColor(p.tierName),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isExplored) ...[
                        Text(
                          '${p.tripCount} chuyến đi • ${p.waypointCount} điểm check-in',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                        if (CompanionQuotes.pickProvinceCardNote(p) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              CompanionQuotes.pickProvinceCardNote(p)!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ] else
                        const Text(
                          'Chưa đặt chân tới • Hãy lên đường khám phá!',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(p.distanceKm > 0 ? p.distanceKm : p.traveledKm).toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isExplored ? AppTheme.primary : Colors.grey,
                      ),
                    ),
                    if (isExplored && p.distanceKm > 0 && p.traveledKm > p.distanceKm + 0.1)
                      Text(
                        'Tổng đi: ${p.traveledKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
