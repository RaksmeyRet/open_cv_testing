import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/photo_library_controller.dart';

class PhotoLibraryScreen extends GetView<PhotoLibraryController> {
  const PhotoLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(PhotoLibraryController());
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF092469),
        elevation: 0,
        title: const Text(
          'រូបថត',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Obx(
            () =>
                controller.isLimitedAccess.value
                    ? TextButton(
                      onPressed: controller.presentLimitedPicker,
                      child: const Text('Select more photos'),
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.message.value != null) return _buildMessage();
        if (controller.photos.isEmpty && controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return GridView.builder(
          controller: controller.scrollController,
          padding: const EdgeInsets.all(3),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
          ),
          itemCount:
              controller.photos.length + (controller.hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == controller.photos.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final asset = controller.photos[index];
            return _PhotoTile(
              asset: asset,
              onTap: () => controller.selectPhoto(asset),
            );
          },
        );
      }),
    );
  }

  Widget _buildMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 52,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(height: 16),
            Obx(
              () =>
                  Text(controller.message.value!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller.reload,
              child: const Text('Allow access'),
            ),
            Obx(
              () =>
                  controller.isPermissionDenied.value
                      ? Column(
                        children: [
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: controller.openAppSettings,
                            child: const Text('Open settings'),
                          ),
                        ],
                      )
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: FutureBuilder<Uint8List?>(
        future: asset.thumbnailDataWithSize(const ThumbnailSize(360, 360)),
        builder: (context, snapshot) {
          final thumbnail = snapshot.data;
          if (thumbnail == null) {
            return const ColoredBox(color: Color(0xFFEAEAEA));
          }
          return Image.memory(thumbnail, fit: BoxFit.cover);
        },
      ),
    );
  }
}
