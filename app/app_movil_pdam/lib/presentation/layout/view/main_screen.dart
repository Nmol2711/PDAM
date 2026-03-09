import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/presentation/layout/view/main_screen_desktop.dart';
import 'package:app_movil_pdam/presentation/layout/view/main_screen_mobile.dart';
import 'package:app_movil_pdam/presentation/layout/view/main_screen_tablet.dart';
import 'package:app_movil_pdam/presentation/layout/widgets/drawer_widget.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/responsive_widget.dart';
import 'package:flutter/material.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveWidget.isMobile(context);

    return Scaffold(
      appBar: AppBar(title: Text(appName)),
      drawer: isMobile
          ? Drawer(
              backgroundColor: AppColors.purpleBackgroud,
              child: DrawerWidget(),
            )
          : null,
      body: ResponsiveWidget(
        mobile: MainScreenMobile(),
        tablet: MainScreenTablet(),
        desktop: MainScreenDesktop(),
      ),
    );
  }
}
