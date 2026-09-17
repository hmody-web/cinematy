import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'football_match_models.dart';
import 'sports_match_hero_service.dart';

class MobileMatchHeroCarousel extends StatelessWidget {
  const MobileMatchHeroCarousel({
    super.key,
    required this.items,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onWatch,
  });

  final List<SportsMatchHeroData> items;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<SportsMatchHeroData> onWatch;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight * 1.08;
        return Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: controller,
              itemCount: items.length,
              onPageChanged: onPageChanged,
              allowImplicitScrolling: true,
              physics: const PageScrollPhysics(),
              itemBuilder: (context, index) {
                final data = items[index];
                // Keep the expensive cinematic artwork isolated from the page
                // movement. PageView handles only a lightweight slide instead
                // of rebuilding opacity/scale/translation every frame.
                return RepaintBoundary(
                  child: _MobileMatchHero(
                    data: data,
                    landscape: landscape,
                    onWatch: data.match.isLive ? () => onWatch(data) : null,
                  ),
                );
              },
            ),
            if (items.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: landscape ? 10 : 12,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(items.length, (index) {
                      final selected = index == currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: selected ? 22 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.white.withOpacity(.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MobileMatchHero extends StatelessWidget {
  const _MobileMatchHero({
    required this.data,
    required this.landscape,
    required this.onWatch,
  });

  final SportsMatchHeroData data;
  final bool landscape;
  final VoidCallback? onWatch;

  static const Map<String, String> _leagueArabic = <String, String>{
    'uefa champions league': 'دوري أبطال أوروبا',
    'champions league': 'دوري أبطال أوروبا',
    'english premier league': 'الدوري الإنجليزي الممتاز',
    'premier league': 'الدوري الإنجليزي الممتاز',
    'la liga': 'الدوري الإسباني',
    'spanish la liga': 'الدوري الإسباني',
    'serie a': 'الدوري الإيطالي',
    'italian serie a': 'الدوري الإيطالي',
    'bundesliga': 'الدوري الألماني',
    'german bundesliga': 'الدوري الألماني',
    'ligue 1': 'الدوري الفرنسي',
    'french ligue 1': 'الدوري الفرنسي',
  };

  static const Map<String, String> _teamArabic = <String, String>{
    // Spain
    'real madrid': 'ريال مدريد',
    'real madrid cf': 'ريال مدريد',
    'barcelona': 'برشلونة',
    'fc barcelona': 'برشلونة',
    'atletico madrid': 'أتلتيكو مدريد',
    'atletico de madrid': 'أتلتيكو مدريد',
    'athletic club': 'أتلتيك بلباو',
    'athletic bilbao': 'أتلتيك بلباو',
    'real betis': 'ريال بيتيس',
    'getafe': 'خيتافي',
    'getafe cf': 'خيتافي',
    'real sociedad': 'ريال سوسيداد',
    'villarreal': 'فياريال',
    'villarreal cf': 'فياريال',
    'sevilla': 'إشبيلية',
    'sevilla fc': 'إشبيلية',
    'valencia': 'فالنسيا',
    'valencia cf': 'فالنسيا',
    'celta vigo': 'سيلتا فيغو',
    'celta de vigo': 'سيلتا فيغو',
    'osasuna': 'أوساسونا',
    'ca osasuna': 'أوساسونا',
    'mallorca': 'ريال مايوركا',
    'rcd mallorca': 'ريال مايوركا',
    'girona': 'جيرونا',
    'girona fc': 'جيرونا',
    'rayo vallecano': 'رايو فايكانو',
    'espanyol': 'إسبانيول',
    'rcd espanyol': 'إسبانيول',
    'alaves': 'ديبورتيفو ألافيس',
    'deportivo alaves': 'ديبورتيفو ألافيس',
    'levante': 'ليفانتي',
    'elche': 'إلتشي',
    'las palmas': 'لاس بالماس',
    'real oviedo': 'ريال أوفييدو',
    'malaga': 'مالقة',
    'malaga cf': 'مالقة',

    // England
    'arsenal': 'أرسنال',
    'arsenal fc': 'أرسنال',
    'manchester city': 'مانشستر سيتي',
    'man city': 'مانشستر سيتي',
    'manchester united': 'مانشستر يونايتد',
    'man united': 'مانشستر يونايتد',
    'liverpool': 'ليفربول',
    'chelsea': 'تشيلسي',
    'tottenham hotspur': 'توتنهام هوتسبير',
    'tottenham': 'توتنهام هوتسبير',
    'newcastle united': 'نيوكاسل يونايتد',
    'aston villa': 'أستون فيلا',
    'crystal palace': 'كريستال بالاس',
    'brighton': 'برايتون',
    'brighton and hove albion': 'برايتون',
    'west ham united': 'وست هام يونايتد',
    'west ham': 'وست هام يونايتد',
    'everton': 'إيفرتون',
    'fulham': 'فولهام',
    'brentford': 'برينتفورد',
    'bournemouth': 'بورنموث',
    'afc bournemouth': 'بورنموث',
    'wolverhampton wanderers': 'وولفرهامبتون',
    'wolves': 'وولفرهامبتون',
    'nottingham forest': 'نوتنغهام فورست',
    'leeds united': 'ليدز يونايتد',
    'leicester city': 'ليستر سيتي',
    'southampton': 'ساوثهامبتون',
    'burnley': 'بيرنلي',
    'sunderland': 'سندرلاند',
    'ipswich town': 'إيبسويتش تاون',

    // Italy
    'juventus': 'يوفنتوس',
    'inter': 'إنتر ميلان',
    'inter milan': 'إنتر ميلان',
    'internazionale': 'إنتر ميلان',
    'ac milan': 'ميلان',
    'milan': 'ميلان',
    'napoli': 'نابولي',
    'roma': 'روما',
    'as roma': 'روما',
    'lazio': 'لاتسيو',
    'atalanta': 'أتالانتا',
    'fiorentina': 'فيورنتينا',
    'bologna': 'بولونيا',
    'torino': 'تورينو',
    'udinese': 'أودينيزي',
    'genoa': 'جنوى',
    'como': 'كومو',
    'parma': 'بارما',
    'lecce': 'ليتشي',
    'cagliari': 'كالياري',
    'hellas verona': 'هيلاس فيرونا',
    'verona': 'هيلاس فيرونا',
    'sassuolo': 'ساسولو',
    'cremonese': 'كريمونيزي',
    'pisa': 'بيزا',
    'monza': 'مونزا',
    'empoli': 'إمبولي',

    // Germany
    'bayern munich': 'بايرن ميونخ',
    'fc bayern munich': 'بايرن ميونخ',
    'bayern munchen': 'بايرن ميونخ',
    'borussia dortmund': 'بوروسيا دورتموند',
    'bayer leverkusen': 'باير ليفركوزن',
    'rb leipzig': 'لايبزيغ',
    'rbl': 'لايبزيغ',
    'eintracht frankfurt': 'آينتراخت فرانكفورت',
    'vfb stuttgart': 'شتوتغارت',
    'stuttgart': 'شتوتغارت',
    'sc freiburg': 'فرايبورغ',
    'freiburg': 'فرايبورغ',
    'hoffenheim': 'هوفنهايم',
    'tsg hoffenheim': 'هوفنهايم',
    'wolfsburg': 'فولفسبورغ',
    'vfl wolfsburg': 'فولفسبورغ',
    'werder bremen': 'فيردر بريمن',
    'augsburg': 'أوغسبورغ',
    'fc augsburg': 'أوغسبورغ',
    'mainz': 'ماينز',
    'mainz 05': 'ماينز',
    'borussia monchengladbach': 'بوروسيا مونشنغلادباخ',
    'monchengladbach': 'بوروسيا مونشنغلادباخ',
    'union berlin': 'يونيون برلين',
    'st pauli': 'سانت باولي',
    'hamburg': 'هامبورغ',
    'hamburger sv': 'هامبورغ',
    'koln': 'كولن',
    'cologne': 'كولن',
    'heidenheim': 'هايدنهايم',

    // France
    'paris saint germain': 'باريس سان جيرمان',
    'paris saint-germain': 'باريس سان جيرمان',
    'psg': 'باريس سان جيرمان',
    'marseille': 'مارسيليا',
    'olympique marseille': 'مارسيليا',
    'monaco': 'موناكو',
    'as monaco': 'موناكو',
    'lyon': 'ليون',
    'olympique lyonnais': 'ليون',
    'lille': 'ليل',
    'losc lille': 'ليل',
    'nice': 'نيس',
    'ogc nice': 'نيس',
    'rennes': 'رين',
    'stade rennais': 'رين',
    'strasbourg': 'ستراسبورغ',
    'lens': 'لانس',
    'rc lens': 'لانس',
    'brest': 'بريست',
    'nantes': 'نانت',
    'toulouse': 'تولوز',
    'auxerre': 'أوكسير',
    'angers': 'أنجيه',
    'le havre': 'لوهافر',
    'metz': 'ميتز',
    'lorient': 'لوريان',
    'paris fc': 'باريس إف سي',

    // Common UEFA Champions League clubs outside the big five
    'benfica': 'بنفيكا',
    'sl benfica': 'بنفيكا',
    'sporting cp': 'سبورتينغ لشبونة',
    'sporting lisbon': 'سبورتينغ لشبونة',
    'porto': 'بورتو',
    'fc porto': 'بورتو',
    'ajax': 'أياكس',
    'psv': 'بي إس في آيندهوفن',
    'psv eindhoven': 'بي إس في آيندهوفن',
    'feyenoord': 'فينورد',
    'celtic': 'سلتيك',
    'rangers': 'رينجرز',
    'galatasaray': 'غلطة سراي',
    'fenerbahce': 'فنربخشة',
    'besiktas': 'بشكتاش',
    'club brugge': 'كلوب بروج',
    'anderlecht': 'أندرلخت',
    'olympiacos': 'أولمبياكوس',
    'olympiakos': 'أولمبياكوس',
    'panathinaikos': 'باناثينايكوس',
    'shakhtar donetsk': 'شاختار دونيتسك',
    'dynamo kyiv': 'دينامو كييف',
    'red star belgrade': 'النجم الأحمر بلغراد',
    'crvena zvezda': 'النجم الأحمر بلغراد',
    'red bull salzburg': 'ريد بول سالزبورغ',
    'salzburg': 'سالزبورغ',
    'sparta prague': 'سبارتا براغ',
    'slavia prague': 'سلافيا براغ',
    'viktoria plzen': 'فيكتوريا بلزن',
    'dinamo zagreb': 'دينامو زغرب',
    'young boys': 'يونغ بويز',
    'fc copenhagen': 'كوبنهاغن',
    'copenhagen': 'كوبنهاغن',
    'bodo glimt': 'بودو غليمت',
    'bodo/glimt': 'بودو غليمت',
    'malmo': 'مالمو',
    'qarabag': 'قره باغ',
    'maccabi tel aviv': 'مكابي تل أبيب',
    'slovan bratislava': 'سلوفان براتيسلافا',
    'sturm graz': 'شتورم غراتس',
  };

  static const Map<String, String> _venueArabic = <String, String>{
    'santiago bernabeu': 'سانتياغو برنابيو',
    'estadio santiago bernabeu': 'سانتياغو برنابيو',
    'spotify camp nou': 'سبوتيفاي كامب نو',
    'camp nou': 'كامب نو',
    'estadi olimpic lluis companys': 'الملعب الأولمبي لويس كومبانيس',
    'metropolitano': 'ميتروبوليتانو',
    'civitas metropolitano': 'ميتروبوليتانو',
    'benito villamarin': 'بينيتو فيامارين',
    'coliseum': 'كوليسيوم',
    'reale arena': 'ريالي أرينا',
    'anoeta': 'أنويتا',
    'estadio de la ceramica': 'ملعب لا سيراميكا',
    'san mames': 'سان ماميس',
    'mestalla': 'ميستايا',
    'ramon sanchez pizjuan': 'رامون سانشيز بيزخوان',
    'old trafford': 'أولد ترافورد',
    'etihad stadium': 'ملعب الاتحاد',
    'emirates stadium': 'ملعب الإمارات',
    'anfield': 'أنفيلد',
    'stamford bridge': 'ستامفورد بريدج',
    'tottenham hotspur stadium': 'ملعب توتنهام هوتسبير',
    'selhurst park': 'سيلهرست بارك',
    'villa park': 'فيلا بارك',
    'st james park': 'سانت جيمس بارك',
    'goodison park': 'غوديسون بارك',
    'hill dickinson stadium': 'ملعب هيل ديكنسون',
    'allianz arena': 'أليانز أرينا',
    'signal iduna park': 'سيغنال إيدونا بارك',
    'bayarena': 'باي أرينا',
    'red bull arena': 'ريد بول أرينا',
    'deutsche bank park': 'دويتشه بنك بارك',
    'mhparena': 'إم إتش بي أرينا',
    'san siro': 'سان سيرو',
    'giuseppe meazza': 'جوزيبي مياتزا',
    'allianz stadium': 'أليانز ستاديوم',
    'stadio diego armando maradona': 'ملعب دييغو أرماندو مارادونا',
    'stadio olimpico': 'الملعب الأولمبي',
    'gewiss stadium': 'ملعب جيويس',
    'stadio renato dall ara': 'ملعب ريناتو دال آرا',
    'parc des princes': 'بارك دي برانس',
    'stade velodrome': 'ملعب فيلودروم',
    'orange velodrome': 'أورانج فيلودروم',
    'groupama stadium': 'ملعب غروباما',
    'stade louis ii': 'ملعب لويس الثاني',
    'estadio da luz': 'ملعب دا لوز',
    'estadio jose alvalade': 'ملعب جوزيه ألفالادي',
    'estadio do dragao': 'ملعب الدراغاو',
    'johan cruyff arena': 'يوهان كرويف أرينا',
    'philips stadion': 'ملعب فيليبس',
    'de kuip': 'دي كويب',
    'celtic park': 'سلتيك بارك',
    'ibrox stadium': 'ملعب آيبروكس',
  };

  String _normal(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _arabicLeagueName(String value) {
    final key = _normal(value);
    final exact = _leagueArabic[key];
    if (exact != null) return exact;
    for (final entry in _leagueArabic.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) return entry.value;
    }
    return value.isEmpty ? 'كرة القدم' : value;
  }

  String _arabicTeamName(String value) {
    final key = _normal(value);
    final exact = _teamArabic[key];
    if (exact != null) return exact;
    final stripped = key
        .replaceAll(RegExp(r'\b(fc|cf|afc|sc|ac)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _teamArabic[stripped] ?? value;
  }

  String _arabicVenueName(String value) {
    if (value.trim().isEmpty) return '';
    final key = _normal(value);
    final exact = _venueArabic[key];
    if (exact != null) return exact;
    return value
        .replaceAll(RegExp(r'\bStadium\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bStade\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bStadio\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bEstadio\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bArena\b', caseSensitive: false), 'أرينا');
  }

  bool _isBein(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return compact.contains('bein') || value.contains('بين') || value.contains('بي إن');
  }

  String _arabicBroadcastName(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    if (_isBein(raw)) {
      final number = RegExp(r'\b(\d{1,2})\b').firstMatch(raw)?.group(1);
      final premium = raw.toLowerCase().contains('premium');
      return 'بي إن سبورتس${premium ? ' بريميوم' : ''}${number == null ? '' : ' $number'}';
    }
    final lower = raw.toLowerCase();
    if (lower.contains('sky sports')) return 'سكاي سبورتس';
    if (lower.contains('tnt sports')) return 'تي إن تي سبورتس';
    if (lower.contains('premier sports')) return 'بريمير سبورتس';
    if (lower.contains('dazn')) return 'دازن';
    if (lower.contains('espn')) return 'إي إس بي إن';
    if (lower.contains('canal')) return 'كانال بلس';
    if (lower.contains('paramount')) return 'باراماونت بلس';
    if (lower.contains('amazon')) return 'أمازون برايم';
    if (lower.contains('ssc')) {
      final number = RegExp(r'\b(\d{1,2})\b').firstMatch(raw)?.group(1);
      return 'إس إس سي${number == null ? '' : ' $number'}';
    }
    return raw;
  }

  String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'صباحًا' : 'مساءً'}';
  }

  String _weekday(DateTime value) {
    const days = <int, String>{
      DateTime.monday: 'الاثنين',
      DateTime.tuesday: 'الثلاثاء',
      DateTime.wednesday: 'الأربعاء',
      DateTime.thursday: 'الخميس',
      DateTime.friday: 'الجمعة',
      DateTime.saturday: 'السبت',
      DateTime.sunday: 'الأحد',
    };
    return days[value.weekday] ?? '';
  }

  String _date(DateTime value) {
    const months = <int, String>{
      1: 'يناير', 2: 'فبراير', 3: 'مارس', 4: 'أبريل',
      5: 'مايو', 6: 'يونيو', 7: 'يوليو', 8: 'أغسطس',
      9: 'سبتمبر', 10: 'أكتوبر', 11: 'نوفمبر', 12: 'ديسمبر',
    };
    return '${value.day} ${months[value.month] ?? value.month}';
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return now.year == value.year && now.month == value.month && now.day == value.day;
  }

  String _timeLabel() {
    final match = data.match;
    if (match.isLive) {
      final minute = match.minute;
      return minute == null ? 'مباشر الآن' : 'مباشر الآن • الدقيقة $minute';
    }
    if (match.status == FootballMatchStatus.postponed) return 'المباراة مؤجلة';
    final start = match.startsAt;
    if (start == null) return 'موعد المباراة سيُعلن قريبًا';
    if (!_isToday(start)) {
      return '${_weekday(start)}، ${_date(start)} • ${_clock(start)}';
    }
    return 'تبدأ المباراة الساعة ${_clock(start)}';
  }

  Color _teamColor(String value, Color fallback) {
    var text = value.trim().replaceAll('#', '');
    if (text.length == 6) text = 'FF$text';
    return Color(int.tryParse(text, radix: 16) ?? fallback.value);
  }

  @override
  Widget build(BuildContext context) {
    final match = data.match;
    final homeColor = _teamColor(data.homeColour, const Color(0xFF7D1320));
    final awayColor = _teamColor(data.awayColour, const Color(0xFF143F8E));
    final showScore = (match.isLive || match.isFinished) &&
        match.homeScore != null && match.awayScore != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(landscape ? 0 : 28),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final playerWidth = landscape ? w * .46 : w * .80;
          final playerHeight = landscape ? h * 1.10 : h * .92;
          final badgeSize = landscape ? w * .28 : w * .42;

          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF020203)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      awayColor.withOpacity(.96),
                      awayColor.withOpacity(.44),
                      Colors.black.withOpacity(.24),
                      homeColor.withOpacity(.44),
                      homeColor.withOpacity(.96),
                    ],
                    stops: const [0, .22, .5, .78, 1],
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: landscape ? const Alignment(0, -.08) : const Alignment(0, .15),
                      radius: landscape ? 1.0 : 1.2,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(.30),
                        Colors.black.withOpacity(.86),
                      ],
                      stops: const [.08, .58, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -badgeSize * .16,
                top: landscape ? h * .12 : h * .06,
                width: badgeSize,
                height: badgeSize,
                child: _BackdropBadge(url: data.awayBadge, tint: awayColor),
              ),
              Positioned(
                right: -badgeSize * .16,
                top: landscape ? h * .12 : h * .06,
                width: badgeSize,
                height: badgeSize,
                child: _BackdropBadge(url: data.homeBadge, tint: homeColor),
              ),
              Positioned(
                left: landscape ? -w * .035 : -w * .22,
                bottom: landscape ? -h * .04 : h * .055,
                width: playerWidth,
                height: playerHeight,
                child: _PlayerRender(
                  url: data.awayPlayer,
                  fallback: data.awayBadge,
                  alignment: Alignment.bottomLeft,
                  tint: awayColor,
                ),
              ),
              Positioned(
                right: landscape ? -w * .035 : -w * .22,
                bottom: landscape ? -h * .04 : h * .055,
                width: playerWidth,
                height: playerHeight,
                child: _PlayerRender(
                  url: data.homePlayer,
                  fallback: data.homeBadge,
                  alignment: Alignment.bottomRight,
                  tint: homeColor,
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 44 : 14,
                    landscape ? 18 : 14,
                    landscape ? 44 : 14,
                    landscape ? 24 : 26,
                  ),
                  child: Column(
                    children: [
                      if (data.leagueBadge.isNotEmpty)
                        Image.network(
                          data.leagueBadge,
                          height: landscape ? 58 : 42,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      SizedBox(height: landscape ? 5 : 4),
                      Text(
                        _arabicLeagueName(match.league),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: landscape ? 15 : 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withOpacity(.82),
                          shadows: [Shadow(color: Colors.black.withOpacity(.7), blurRadius: 12)],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        constraints: BoxConstraints(maxWidth: landscape ? 560 : 430),
                        padding: EdgeInsets.fromLTRB(
                          landscape ? 24 : 12,
                          landscape ? 16 : 12,
                          landscape ? 24 : 12,
                          landscape ? 14 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.46),
                          borderRadius: BorderRadius.circular(landscape ? 26 : 22),
                          border: Border.all(color: Colors.white.withOpacity(.08)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.42),
                              blurRadius: 34,
                              spreadRadius: -5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              textDirection: TextDirection.rtl,
                              children: [
                                Expanded(
                                  child: _TeamIdentity(
                                    name: _arabicTeamName(match.homeName),
                                    badge: data.homeBadge,
                                    landscape: landscape,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: landscape ? 16 : 7),
                                  child: Text(
                                    showScore
                                        ? '${match.awayScore} - ${match.homeScore}'
                                        : 'ضد',
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      fontSize: showScore
                                          ? (landscape ? 30 : 22)
                                          : (landscape ? 19 : 15),
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _TeamIdentity(
                                    name: _arabicTeamName(match.awayName),
                                    badge: data.awayBadge,
                                    landscape: landscape,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: landscape ? 12 : 9),
                            Text(
                              _timeLabel(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: match.isLive ? AppColors.redBright : Colors.white.withOpacity(.90),
                                fontSize: landscape ? 14 : 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (data.stadiumName.isNotEmpty) ...[
                              SizedBox(height: landscape ? 7 : 5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.stadium_rounded, size: landscape ? 16 : 14, color: Colors.white54),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      _arabicVenueName(data.stadiumName),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.58),
                                        fontSize: landscape ? 12 : 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (data.broadcastName.isNotEmpty) ...[
                              SizedBox(height: landscape ? 10 : 8),
                              _BroadcasterChip(
                                name: _arabicBroadcastName(data.broadcastName),
                                logo: data.broadcastLogo,
                                isBein: _isBein(data.broadcastName),
                                compact: !landscape,
                              ),
                            ],
                            if (onWatch != null) ...[
                              SizedBox(height: landscape ? 12 : 10),
                              SizedBox(
                                height: landscape ? 44 : 40,
                                child: FilledButton.icon(
                                  onPressed: onWatch,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.redBright,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: landscape ? 24 : 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text(
                                    'شاهد الآن',
                                    style: TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BackdropBadge extends StatelessWidget {
  const _BackdropBadge({required this.url, required this.tint});
  final String url;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Opacity(
      opacity: .11,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(tint.withOpacity(.82), BlendMode.srcATop),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _PlayerRender extends StatelessWidget {
  const _PlayerRender({
    required this.url,
    required this.fallback,
    required this.alignment,
    required this.tint,
  });

  final String url;
  final String fallback;
  final Alignment alignment;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url.isNotEmpty)
          Align(
            alignment: alignment,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: alignment,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          )
        else if (fallback.isNotEmpty)
          Align(
            alignment: alignment,
            child: Opacity(
              opacity: .20,
              child: Image.network(
                fallback,
                fit: BoxFit.contain,
                alignment: alignment,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.48),
                  blurRadius: 42,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TeamIdentity extends StatelessWidget {
  const _TeamIdentity({
    required this.name,
    required this.badge,
    required this.landscape,
  });
  final String name;
  final String badge;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final size = landscape ? 58.0 : 44.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(landscape ? 5 : 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(.10)),
          ),
          child: badge.isEmpty
              ? Icon(Icons.shield_rounded, color: Colors.white38, size: size * .65)
              : Image.network(
                  badge,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.shield_rounded, color: Colors.white38, size: size * .65),
                ),
        ),
        SizedBox(height: landscape ? 8 : 6),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: landscape ? 13.5 : 11,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _BroadcasterChip extends StatelessWidget {
  const _BroadcasterChip({
    required this.name,
    required this.logo,
    required this.isBein,
    required this.compact,
  });
  final String name;
  final String logo;
  final bool isBein;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isBein ? const Color(0xFF8F60FF).withOpacity(.5) : Colors.white.withOpacity(.09),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBein)
            _BeinMark(compact: compact)
          else if (logo.isNotEmpty)
            Image.network(
              logo,
              width: compact ? 22 : 28,
              height: compact ? 22 : 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded, size: 18),
            )
          else
            Icon(Icons.live_tv_rounded, size: compact ? 17 : 20, color: Colors.white70),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10.5 : 12.5,
                fontWeight: FontWeight.w900,
                color: Colors.white.withOpacity(.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BeinMark extends StatelessWidget {
  const _BeinMark({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 6 : 8, compact ? 4 : 5, compact ? 6 : 7, compact ? 4 : 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B45E6), Color(0xFF4D238B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'beIN',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            child: Text(
              'SPORTS',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: const Color(0xFF4D238B),
                fontSize: compact ? 5.5 : 6.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
