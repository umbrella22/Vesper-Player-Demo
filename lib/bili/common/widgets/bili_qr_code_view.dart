import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/bili_models.dart';

class BiliQrCodeView extends StatelessWidget {
  const BiliQrCodeView({
    super.key,
    required this.ticket,
    required this.isLoading,
  });

  final BiliQrLoginTicket? ticket;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ticket = this.ticket;
    if (ticket == null) {
      return const Icon(
        Icons.qr_code_2_rounded,
        size: 88,
        color: Color(0xFF7B8CA1),
      );
    }
    return QrImageView(
      data: ticket.url,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF111A2B),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF111A2B),
      ),
    );
  }
}
