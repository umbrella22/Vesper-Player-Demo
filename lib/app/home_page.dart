import 'package:bilibili_player/bili/bili.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BiliUiMode get _uiMode => initialUiMode;

  @override
  Widget build(BuildContext context) {
    if (_uiMode == BiliUiMode.tv) {
      return const BiliTvHomePage();
    }

    return const BiliHubPage();
  }
}
