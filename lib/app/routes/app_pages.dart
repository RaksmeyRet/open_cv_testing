import 'package:get/get.dart';

import '../../features/id_scan/presentation/pages/scan_page.dart';
import '../../features/id_scan/presentation/bindings/scan_binding.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static final pages = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.scan,
      page: () => const ScanScreen(),
      binding: ScanBinding(),
    ),
  ];
}
