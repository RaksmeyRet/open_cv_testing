import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoLibraryController extends GetxController {
  static const _pageSize = 60;

  final scrollController = ScrollController();
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
    _loadPhotoLibrary();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadPhotoLibrary() async {
    final permission = await PhotoManager.requestPermissionExtend();

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
    await _loadNextPage();
  }

  void _loadMoreWhenNeeded() {
    if (scrollController.position.extentAfter < 360) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

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
    await _loadPhotoLibrary();
  }

  void openAppSettings() => PhotoManager.openSetting();

  Future<void> presentLimitedPicker() async {
    await PhotoManager.presentLimited();
    await reload();
  }
}

