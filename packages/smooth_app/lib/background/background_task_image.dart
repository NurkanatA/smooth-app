import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/background/abstract_background_task.dart';
import 'package:smooth_app/background/background_task_refresh_later.dart';
import 'package:smooth_app/data_models/operation_type.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/database/transient_file.dart';
import 'package:smooth_app/query/product_query.dart';

/// Background task about product image upload.
class BackgroundTaskImage extends AbstractBackgroundTask {
  const BackgroundTaskImage._({
    required super.processName,
    required super.uniqueId,
    required super.barcode,
    required super.languageCode,
    required super.user,
    required super.country,
    required super.stamp,
    required this.imageField,
    required this.imagePath,
  });

  BackgroundTaskImage._fromJson(Map<String, dynamic> json)
      : this._(
          processName: json['processName'] as String,
          uniqueId: json['uniqueId'] as String,
          barcode: json['barcode'] as String,
          languageCode: json['languageCode'] as String,
          user: json['user'] as String,
          country: json['country'] as String,
          imageField: json['imageField'] as String,
          imagePath: json['imagePath'] as String,
          // dealing with when 'stamp' did not exist
          stamp: json.containsKey('stamp')
              ? json['stamp'] as String
              : getStamp(
                  json['barcode'] as String,
                  json['imageField'] as String,
                  json['languageCode'] as String,
                ),
        );

  /// Task ID.
  static const String _PROCESS_NAME = 'IMAGE_UPLOAD';

  static const OperationType _operationType = OperationType.image;

  final String imageField;
  final String imagePath;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'processName': processName,
        'uniqueId': uniqueId,
        'barcode': barcode,
        'languageCode': languageCode,
        'user': user,
        'country': country,
        'imageField': imageField,
        'imagePath': imagePath,
        'stamp': stamp,
      };

  /// Returns the deserialized background task if possible, or null.
  static AbstractBackgroundTask? fromJson(final Map<String, dynamic> map) {
    try {
      final AbstractBackgroundTask result = BackgroundTaskImage._fromJson(map);
      if (result.processName == _PROCESS_NAME) {
        return result;
      }
    } catch (e) {
      //
    }
    return null;
  }

  /// Adds the background task about uploading a product image.
  static Future<void> addTask(
    final String barcode, {
    required final ImageField imageField,
    required final File imageFile,
    required final State<StatefulWidget> widget,
  }) async {
    final LocalDatabase localDatabase = widget.context.read<LocalDatabase>();
    final String uniqueId = await _operationType.getNewKey(
      localDatabase,
      barcode,
    );
    final AbstractBackgroundTask task = _getNewTask(
      barcode,
      imageField,
      imageFile,
      uniqueId,
    );
    await task.addToManager(localDatabase, widget: widget);
  }

  @override
  String? getSnackBarMessage(final AppLocalizations appLocalizations) =>
      appLocalizations.image_upload_queued;

  /// Returns a new background task about changing a product.
  static BackgroundTaskImage _getNewTask(
    final String barcode,
    final ImageField imageField,
    final File imageFile,
    final String uniqueId,
  ) =>
      BackgroundTaskImage._(
        uniqueId: uniqueId,
        barcode: barcode,
        processName: _PROCESS_NAME,
        imageField: imageField.offTag,
        imagePath: imageFile.path,
        languageCode: ProductQuery.getLanguage().code,
        user: jsonEncode(ProductQuery.getUser().toJson()),
        country: ProductQuery.getCountry()!.offTag,
        stamp: getStamp(
          barcode,
          imageField.offTag,
          ProductQuery.getLanguage().code,
        ),
      );

  static String getStamp(
    final String barcode,
    final String imageField,
    final String language,
  ) =>
      '$barcode;image;$imageField;$language';

  /// Returns true if the stamp is an "image/OTHER" stamp.
  ///
  /// That's important because "image/OTHER" task are never duplicates.
  static bool isOtherStamp(final String stamp) =>
      stamp.contains(';image;${ImageField.OTHER.offTag};');

  @override
  Future<void> preExecute(final LocalDatabase localDatabase) async =>
      TransientFile.putImage(
        ImageField.fromOffTag(imageField)!,
        barcode,
        localDatabase,
        File(imagePath),
      );

  // TODO(monsieurtanuki): we may also need to remove old files that were not removed from some reason
  @override
  Future<void> postExecute(final LocalDatabase localDatabase) async {
    try {
      File(imagePath).deleteSync();
    } catch (e) {
      // not likely, but let's not spoil the task for that either.
    }
    TransientFile.removeImage(
      ImageField.fromOffTag(imageField)!,
      barcode,
      localDatabase,
    );
    localDatabase.notifyListeners();
    await BackgroundTaskRefreshLater.addTask(
      barcode,
      localDatabase: localDatabase,
    );
  }

  /// Uploads the product image.
  @override
  Future<void> upload() async {
    final SendImage image = SendImage(
      lang: getLanguage(),
      barcode: barcode,
      imageField: ImageField.fromOffTag(imageField)!,
      imageUri: Uri.parse(imagePath),
    );

    final Status status =
        await OpenFoodAPIClient.addProductImage(getUser(), image);
    if (status.status == 'status ok') {
      return;
    }
    throw Exception(
        'Could not upload picture: ${status.status} / ${status.error}');
  }
}
