import 'package:review_ai/widgets/common/app_dialogs.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:review_ai/providers/review_provider.dart';

final isPickingImageProvider = StateProvider<bool>((ref) => false);

class ImageUploadSection extends ConsumerWidget {
  const ImageUploadSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewState = ref.watch(reviewProvider);
    final image = reviewState.image;
    final isPicking = ref.watch(isPickingImageProvider);

    return GestureDetector(
      onTap: isPicking ? null : () => _pickImage(ref, context),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.grey[300]!, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha((255 * 0.05).round()),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              _buildImageContent(context, image, isPicking),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("좋은 사진 선택 팁"),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("✓ 음식 전체가 잘 보이는 사진"),
                            Text("✓ 조명이 밝고 선명한 사진"),
                            Text("✓ 접시나 용기까지 포함된 사진"),
                            Text("✗ 일부만 보이거나 흐린 사진"),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(
    BuildContext context,
    File? imageFile,
    bool isPicking,
  ) {
    if (isPicking) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12.0),
            Text(
              '이미지 처리 중...',
              style: TextStyle(
                fontSize: 14.0,
                fontFamily: 'SCDream',
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 4.0),
            Text(
              '잠시만 기다려주세요',
              style: TextStyle(
                fontSize: 12.0,
                fontFamily: 'SCDream',
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (imageFile == null || !imageFile.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 48.0,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16.0),
            Text(
              '이미지 업로드',
              style: TextStyle(
                fontSize: 16.0,
                fontFamily: 'SCDream',
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              '탭하여 사진 선택',
              style: TextStyle(
                fontSize: 12.0,
                fontFamily: 'SCDream',
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        image: DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover),
      ),
    );
  }

  void _pickImage(WidgetRef ref, BuildContext context) async {
    if (ref.read(isPickingImageProvider)) return;

    ref.read(isPickingImageProvider.notifier).state = true;
    try {
      final picker = ImagePicker();

      // 향상된 이미지 선택 옵션
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );

      // 🔒 권한 거부 처리: picked가 null이면 사용자가 취소했거나 권한이 없음
      if (picked == null) {
        // 사용자가 직접 취소한 경우는 조용히 리턴
        ref.read(isPickingImageProvider.notifier).state = false;
        return;
      }

      final imageFile = File(picked.path);

      // 파일 존재 확인
      if (!await imageFile.exists()) {
        throw Exception('선택된 이미지 파일을 찾을 수 없습니다');
      }

      // 파일 크기 체크 (10MB 제한)
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('이미지 파일이 너무 큽니다.\n10MB 이하의 이미지를 선택해주세요.');
      }

      if (fileSize == 0) {
        throw Exception('선택된 이미지 파일이 손상되었습니다.');
      }

      debugPrint(
        '선택된 이미지: ${imageFile.path}, 크기: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );

      // 약간의 지연을 추가하여 사용자 경험 개선
      await Future.delayed(const Duration(milliseconds: 500));

      ref.read(reviewProvider.notifier).setImage(imageFile);
    } catch (e) {
      if (!context.mounted) return;

      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }

      showAppDialog(
        context,
        title: '이미지 선택 오류',
        message: errorMessage,
        isError: true,
      );
    } finally {
      if (context.mounted) {
        ref.read(isPickingImageProvider.notifier).state = false;
      }
    }
  }
}
