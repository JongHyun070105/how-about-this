import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:review_ai/models/food_category.dart';

class CategoryCard extends StatelessWidget {
  final FoodCategory category;
  final VoidCallback onTap;

  const CategoryCard({super.key, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: Hero(
        tag: 'category_${category.name}',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 100),
            child: Card(
              color: category.color,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.0375),
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: screenWidth * 0.0025,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Expanded(
                    child: SvgPicture.asset(
                      category.imageUrl,
                      fit: BoxFit.contain,
                      width: screenWidth * 0.22,
                      height: screenWidth * 0.22,
                      placeholderBuilder: (context) => Container(
                        color: Colors.grey.shade200,
                        child: Center(
                          child: Icon(Icons.image, size: screenWidth * 0.17),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      top: screenHeight * 0.002,
                      left: screenWidth * 0.02,
                      right: screenWidth * 0.02,
                      bottom: screenHeight * 0.02,
                    ),
                    child: Text(
                      category.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Do Hyeon',
                        fontSize: screenWidth * 0.045,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
