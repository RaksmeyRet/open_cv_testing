import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoLibraryScreen extends StatefulWidget {
  const PhotoLibraryScreen({super.key});

  @override
  State<PhotoLibraryScreen> createState() => _PhotoLibraryScreenState();
}

class _PhotoLibraryScreenState extends State<PhotoLibraryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<AssetEntity> _photos = [];
  static const _pageSize = 60;

  AssetPathEntity? _album;
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isPermissionDenied = false;
  bool _isLimitedAccess = false;
  String? _message;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    _loadPhotoLibrary();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadPhotoLibrary() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;

    if (!permission.hasAccess) {
      setState(() {
        _isLoading = false;
        _isPermissionDenied = true;
        _message = 'Photo access is needed to select an ID card image.';
      });
      return;
    }

    setState(() {
      _isPermissionDenied = false;
      _isLimitedAccess = permission == PermissionState.limited;
      _message = null;
    });

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = 'No photos were found on this device.';
        });
      }
      return;
    }
    _album = albums.first;
    await _loadNextPage();
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter < 360) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    final album = _album;
    if (album == null || _isLoading && _page > 0 || !_hasMore) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      final nextPage = await album.getAssetListPaged(
        page: _page,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _photos.addAll(nextPage);
        _page++;
        _hasMore = nextPage.length == _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = 'Could not load your photos.';
        });
      }
    }
  }

  Future<void> _selectPhoto(AssetEntity asset) async {
    final imageFile = await asset.file;
    if (!mounted || imageFile == null) return;
    Navigator.of(context).pop<File>(imageFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF17191A),
        elevation: 0,
        title: const Text(
          'រូបភាព',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isLimitedAccess)
            TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited();
                await _reload();
              },
              child: const Text('Select more photos'),
            ),
        ],
      ),
      body:
          _message != null
              ? _buildMessage()
              : _photos.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(3),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                ),
                itemCount: _photos.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _photos.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _PhotoTile(
                    asset: _photos[index],
                    onTap: () => _selectPhoto(_photos[index]),
                  );
                },
              ),
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
            Text(_message!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _reload,
              child: const Text('Allow access'),
            ),
            if (_isPermissionDenied) ...[
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

  Future<void> _reload() async {
    setState(() {
      _photos.clear();
      _page = 0;
      _hasMore = true;
      _isLoading = true;
      _message = null;
    });
    await _loadPhotoLibrary();
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
            return const ColoredBox(color: Color(0xFFF1F3F5));
          }
          return Image.memory(thumbnail, fit: BoxFit.cover);
        },
      ),
    );
  }
}
