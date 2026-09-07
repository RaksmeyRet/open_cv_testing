import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../app/theme/app_colors.dart';

class PhotoLibraryController extends GetxController {
  static const _pageSize = 60;

  final ScrollController scrollController = ScrollController();
  final photos = <AssetEntity>[].obs;
  final album = Rxn<AssetPathEntity>();
  final isLoading = true.obs;
  final hasMore = true.obs;
  final isPermissionDenied = false.obs;
  final isLimitedAccess = false.obs;
  final message = RxnString();
  final page = 0.obs;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_loadMoreWhenNeeded);
    loadPhotoLibrary();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.onClose();
  }

  Future<void> loadPhotoLibrary() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!Get.context!.mounted) return;

    if (!permission.hasAccess) {
      isLoading.value = false;
      isPermissionDenied.value = true;
      message.value = 'Photo access is needed to select an ID card image.';
      return;
    }

    isPermissionDenied.value = false;
    isLimitedAccess.value = permission == PermissionState.limited;
    message.value = null;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      isLoading.value = false;
      message.value = 'No photos were found on this device.';
      return;
    }

    album.value = albums.first;
    await loadNextPage();
  }

  void _loadMoreWhenNeeded() {
    if (scrollController.position.extentAfter < 360) {
      loadNextPage();
    }
  }

  Future<void> loadNextPage() async {
    final currentAlbum = album.value;
    if (currentAlbum == null ||
        (isLoading.value && page.value > 0) ||
        !hasMore.value) {
      return;
    }

    isLoading.value = true;

    try {
      final nextPage = await currentAlbum.getAssetListPaged(
        page: page.value,
        size: _pageSize,
      );

      if (!Get.isRegistered<PhotoLibraryController>()) return;

      photos.addAll(nextPage);
      page.value++;
      hasMore.value = nextPage.length == _pageSize;
      isLoading.value = false;
    } catch (_) {
      isLoading.value = false;
      message.value = 'Could not load your photos.';
    }
  }

  Future<void> selectPhoto(AssetEntity asset) async {
    final imageFile = await asset.file;
    if (imageFile == null) return;
    Get.back(result: imageFile);
  }

  Future<void> reload() async {
    photos.clear();
    page.value = 0;
    hasMore.value = true;
    isLoading.value = true;
    message.value = null;
    await loadPhotoLibrary();
  }
}

class PhotoLibraryScreen extends GetView<PhotoLibraryController> {
  const PhotoLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(PhotoLibraryController());

    return Scaffold(
      backgroundColor: AppColors.whiteColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        foregroundColor: AppColors.primaryColor,
        elevation: 0,
        title: const Text(
          'រូបថត',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (controller.isLimitedAccess.value)
            TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited();
                await controller.reload();
              },
              child: const Text('Select more photos'),
            ),
        ],
      ),
      body: Obx(() {
        if (controller.message.value != null) {
          return _buildMessage(controller);
        }

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
            return _PhotoTile(
              asset: controller.photos[index],
              onTap: () => controller.selectPhoto(controller.photos[index]),
            );
          },
        );
      }),
    );
  }

  Widget _buildMessage(PhotoLibraryController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 52,
              color: AppColors.hintColor,
            ),
            const SizedBox(height: 16),
            Text(controller.message.value!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller.reload,
              child: const Text('Allow access'),
            ),
            if (controller.isPermissionDenied.value) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: PhotoManager.openSetting,
                child: const Text('Open settings'),
              ),
            ],
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
            return const ColoredBox(color: AppColors.strokeColor);
          }
          return Image.memory(thumbnail, fit: BoxFit.cover);
        },
      ),
    );
  }
}
