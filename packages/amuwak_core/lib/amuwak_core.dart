/// Public API of the shared Amuwak core package.
///
/// Later tasks add `export 'src/...';` lines here as sources move in.
library;

export 'src/shared/phone.dart';
export 'src/shared/uuid.dart';
export 'src/shared/format_ugx.dart';
export 'src/shared/order_code.dart';
export 'src/shared/email_validation.dart';

// Domain enums
export 'src/orders/order_status.dart';
export 'src/orders/service_type.dart';

// Design system — theme tokens
export 'src/shared/theme/app_colors.dart';
export 'src/shared/theme/app_radii.dart';
export 'src/shared/theme/app_spacing.dart';
export 'src/shared/theme/app_elevation.dart';
export 'src/shared/theme/app_motion.dart';
export 'src/shared/theme/app_typography.dart';
export 'src/shared/theme/status_colors.dart';
export 'src/shared/theme/app_card.dart';

// Design system — motion
export 'src/shared/motion/animated_gradient_header.dart';
export 'src/shared/motion/count_up_text.dart';
export 'src/shared/motion/pressable_scale.dart';
export 'src/shared/motion/reveal_on_mount.dart';

// Design system — widgets
export 'src/shared/widgets/app_theme.dart';
export 'src/shared/widgets/empty_state.dart';
