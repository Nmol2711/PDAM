import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/presentation/auth/views/login/login_screen_desktop.dart';
import 'package:app_movil_pdam/presentation/auth/views/login/login_screen_mobile.dart';
import 'package:app_movil_pdam/presentation/auth/views/login/login_screen_tablet.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/responsive_widget.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: const ResponsiveWidget(
        mobile: LoginScreenMobile(),
        tablet: LoginScreenTablet(),
        desktop: LoginScreenDesktop(),
      ),
    );
  }
}
