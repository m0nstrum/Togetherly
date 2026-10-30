import 'dart:io';

import '../../logic/photo_day_widget_logic.dart';
import '../../services/home_widget_service.dart';

/// Фото-виджеты на рабочем столе, какими их видит экран виджетов: личные и
/// партнёрские отдельно, у каждого имя, превью, ссылки и ротация.
///
/// Снимок неизменяемый: экран целиком подменяет его после загрузки, выбора
/// или переименования.
class PhotoDayWidgets {
  const PhotoDayWidgets({
    this.personalIds = const [],
    this.partnerIds = const [],
    this.names = const {},
    this.ownPhotoPaths = const {},
    this.urls = const {},
    this.rotationType = const {},
    this.rotationInterval = const {},
    this.selectedPersonal,
    this.selectedPartner,
  });

  static const empty = PhotoDayWidgets();

  final List<int> personalIds;
  final List<int> partnerIds;
  final Map<int, String> names;
  final Map<int, String?> ownPhotoPaths;

  /// Per-widget кеш URL-ов (длина → счётчик в превью).
  final Map<int, List<String>> urls;

  /// Per-widget настройки ротации (для подсказок в превью).
  final Map<int, String> rotationType;
  final Map<int, int> rotationInterval;
  final int? selectedPersonal;
  final int? selectedPartner;

  PhotoDayWidgets _copy({
    Map<int, String>? names,
    int? selectedPersonal,
    int? selectedPartner,
  }) => PhotoDayWidgets(
    personalIds: personalIds,
    partnerIds: partnerIds,
    names: names ?? this.names,
    ownPhotoPaths: ownPhotoPaths,
    urls: urls,
    rotationType: rotationType,
    rotationInterval: rotationInterval,
    selectedPersonal: selectedPersonal ?? this.selectedPersonal,
    selectedPartner: selectedPartner ?? this.selectedPartner,
  );

  /// Выбирает виджет [widgetId] в его карточке.
  PhotoDayWidgets select(int widgetId, {required bool partner}) => partner
      ? _copy(selectedPartner: widgetId)
      : _copy(selectedPersonal: widgetId);

  PhotoDayWidgets renamed(int widgetId, String name) =>
      _copy(names: Map<int, String>.from(names)..[widgetId] = name);

  /// Показывать ли в паре [pairId] виджет, привязанный к группе [groupId].
  ///
  /// Без пары — виджеты без группы и «solo»; в паре — свои и ещё не
  /// привязанные.
  static bool listed(String pairId, String? groupId) => pairId.isEmpty
      ? (groupId == null || groupId.isEmpty || groupId == 'solo')
      : (groupId == pairId || groupId == null);

  /// Превью: для личного виджета сначала свои URL, для партнёрского —
  /// фото партнёра из Firestore, чтобы карточка сразу показывала именно его.
  static String? previewPath({
    required bool isPartner,
    required List<String> widgetUrls,
    required String? widgetPreviewPath,
    required String? partnerSharedPreviewPath,
  }) {
    if (isPartner) {
      return partnerSharedPreviewPath ?? widgetPreviewPath;
    }

    if (widgetUrls.isNotEmpty) return widgetUrls.first;
    return widgetPreviewPath;
  }

  /// Читает виджеты пары [pairId] у [HomeWidgetService]. Выбор в карточках
  /// сохраняется, если выбранный виджет ещё стоит на столе.
  static Future<PhotoDayWidgets> load({
    required String pairId,
    required int? selectedPersonal,
    required int? selectedPartner,
    required String? partnerSharedPreviewPath,
  }) async {
    final hws = HomeWidgetService.instance;
    final allIds = await hws.getPhotoDayWidgetIds();
    final rawPersonalIds = await hws.getSelfPhotoWidgetIds();
    final rawPartnerIds = await hws.getPartnerPhotoWidgetIds();
    final personalIds = <int>[];
    final partnerIds = <int>[];

    for (final id in rawPersonalIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      if (listed(pairId, widgetGroupId)) personalIds.add(id);
    }

    for (final id in rawPartnerIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      if (listed(pairId, widgetGroupId)) partnerIds.add(id);
    }

    final widgetNames = <int, String>{};
    final widgetOwnPhotoPaths = <int, String?>{};
    final widgetUrls = <int, List<String>>{};
    final widgetRotationType = <int, String>{};
    final widgetRotationInterval = <int, int>{};

    for (final widgetId in allIds) {
      widgetNames[widgetId] = (await hws.getPhotoDayWidgetName(widgetId)) ?? '';
      final widgetDisplay = await hws.getPhotoDayWidgetDisplay(widgetId);
      final widgetMode = await hws.getPhotoDayWidgetMode(
        widgetId,
        fallbackGroupId: pairId,
      );
      final preview = await hws.getPhotoDayWidgetPreview(widgetId);
      var customPath = await hws.getPhotoDayWidgetCustomPath(widgetId);
      if (customPath != null &&
          customPath.isNotEmpty &&
          !File(customPath).existsSync()) {
        customPath = null;
      }
      final urls = await hws.getPhotoDayWidgetUrls(widgetId);
      widgetUrls[widgetId] = urls;
      widgetRotationType[widgetId] = await hws.getPhotoDayWidgetRotationType(
        widgetId,
      );
      widgetRotationInterval[widgetId] = await hws
          .getPhotoDayWidgetRotationInterval(widgetId);

      final preferredOwnPath = previewPath(
        isPartner: widgetDisplay == 'partner',
        widgetUrls: urls,
        widgetPreviewPath: preview['path'],
        partnerSharedPreviewPath: partnerSharedPreviewPath,
      );

      // myPhotoUrl (Firestore) используется только если у виджета есть
      // собственные URL — иначе новый виджет копировал бы превью уже
      // настроенного виджета.
      final widgetState = PhotoDayWidgetLogic.resolveState(
        selectedWidgetId: widgetId,
        mode: widgetMode,
        display: widgetDisplay,
        widgetPreviewPath: preview['path'],
        widgetCustomPath: customPath,
        fallbackPartnerPhotoPath: partnerSharedPreviewPath,
      );
      widgetOwnPhotoPaths[widgetId] =
          preferredOwnPath ?? widgetState.ownPhotoPath;
    }

    return PhotoDayWidgets(
      personalIds: personalIds,
      partnerIds: partnerIds,
      names: widgetNames,
      ownPhotoPaths: widgetOwnPhotoPaths,
      urls: widgetUrls,
      rotationType: widgetRotationType,
      rotationInterval: widgetRotationInterval,
      selectedPersonal: PhotoDayWidgetLogic.resolveSelectedWidgetId(
        personalIds,
        selectedPersonal,
      ),
      selectedPartner: PhotoDayWidgetLogic.resolveSelectedWidgetId(
        partnerIds,
        selectedPartner,
      ),
    );
  }
}
