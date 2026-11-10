import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/common/widgets/app_qr_code_view.dart';
import 'package:vesper_media/media/design/app_icons.dart';

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
        AppIcons.qrCodeLine,
        size: 88,
        color: Color(0xFF7B8CA1),
      );
    }
    return AppQrCodeView(
      data: ticket.url,
      color: const Color(0xFF111A2B),
    );
  }
}
