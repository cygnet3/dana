// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'frigate_scan_outcome.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$FrigateScanOutcome {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() completed,
    required TResult Function(String reason) disconnected,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? completed,
    TResult? Function(String reason)? disconnected,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? completed,
    TResult Function(String reason)? disconnected,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(FrigateScanOutcome_Completed value) completed,
    required TResult Function(FrigateScanOutcome_Disconnected value)
        disconnected,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(FrigateScanOutcome_Completed value)? completed,
    TResult? Function(FrigateScanOutcome_Disconnected value)? disconnected,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(FrigateScanOutcome_Completed value)? completed,
    TResult Function(FrigateScanOutcome_Disconnected value)? disconnected,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FrigateScanOutcomeCopyWith<$Res> {
  factory $FrigateScanOutcomeCopyWith(
          FrigateScanOutcome value, $Res Function(FrigateScanOutcome) then) =
      _$FrigateScanOutcomeCopyWithImpl<$Res, FrigateScanOutcome>;
}

/// @nodoc
class _$FrigateScanOutcomeCopyWithImpl<$Res, $Val extends FrigateScanOutcome>
    implements $FrigateScanOutcomeCopyWith<$Res> {
  _$FrigateScanOutcomeCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FrigateScanOutcome
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$FrigateScanOutcome_CompletedImplCopyWith<$Res> {
  factory _$$FrigateScanOutcome_CompletedImplCopyWith(
          _$FrigateScanOutcome_CompletedImpl value,
          $Res Function(_$FrigateScanOutcome_CompletedImpl) then) =
      __$$FrigateScanOutcome_CompletedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$FrigateScanOutcome_CompletedImplCopyWithImpl<$Res>
    extends _$FrigateScanOutcomeCopyWithImpl<$Res,
        _$FrigateScanOutcome_CompletedImpl>
    implements _$$FrigateScanOutcome_CompletedImplCopyWith<$Res> {
  __$$FrigateScanOutcome_CompletedImplCopyWithImpl(
      _$FrigateScanOutcome_CompletedImpl _value,
      $Res Function(_$FrigateScanOutcome_CompletedImpl) _then)
      : super(_value, _then);

  /// Create a copy of FrigateScanOutcome
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$FrigateScanOutcome_CompletedImpl extends FrigateScanOutcome_Completed {
  const _$FrigateScanOutcome_CompletedImpl() : super._();

  @override
  String toString() {
    return 'FrigateScanOutcome.completed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FrigateScanOutcome_CompletedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() completed,
    required TResult Function(String reason) disconnected,
  }) {
    return completed();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? completed,
    TResult? Function(String reason)? disconnected,
  }) {
    return completed?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? completed,
    TResult Function(String reason)? disconnected,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(FrigateScanOutcome_Completed value) completed,
    required TResult Function(FrigateScanOutcome_Disconnected value)
        disconnected,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(FrigateScanOutcome_Completed value)? completed,
    TResult? Function(FrigateScanOutcome_Disconnected value)? disconnected,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(FrigateScanOutcome_Completed value)? completed,
    TResult Function(FrigateScanOutcome_Disconnected value)? disconnected,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }
}

abstract class FrigateScanOutcome_Completed extends FrigateScanOutcome {
  const factory FrigateScanOutcome_Completed() =
      _$FrigateScanOutcome_CompletedImpl;
  const FrigateScanOutcome_Completed._() : super._();
}

/// @nodoc
abstract class _$$FrigateScanOutcome_DisconnectedImplCopyWith<$Res> {
  factory _$$FrigateScanOutcome_DisconnectedImplCopyWith(
          _$FrigateScanOutcome_DisconnectedImpl value,
          $Res Function(_$FrigateScanOutcome_DisconnectedImpl) then) =
      __$$FrigateScanOutcome_DisconnectedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String reason});
}

/// @nodoc
class __$$FrigateScanOutcome_DisconnectedImplCopyWithImpl<$Res>
    extends _$FrigateScanOutcomeCopyWithImpl<$Res,
        _$FrigateScanOutcome_DisconnectedImpl>
    implements _$$FrigateScanOutcome_DisconnectedImplCopyWith<$Res> {
  __$$FrigateScanOutcome_DisconnectedImplCopyWithImpl(
      _$FrigateScanOutcome_DisconnectedImpl _value,
      $Res Function(_$FrigateScanOutcome_DisconnectedImpl) _then)
      : super(_value, _then);

  /// Create a copy of FrigateScanOutcome
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reason = null,
  }) {
    return _then(_$FrigateScanOutcome_DisconnectedImpl(
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$FrigateScanOutcome_DisconnectedImpl
    extends FrigateScanOutcome_Disconnected {
  const _$FrigateScanOutcome_DisconnectedImpl({required this.reason})
      : super._();

  @override
  final String reason;

  @override
  String toString() {
    return 'FrigateScanOutcome.disconnected(reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FrigateScanOutcome_DisconnectedImpl &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  /// Create a copy of FrigateScanOutcome
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FrigateScanOutcome_DisconnectedImplCopyWith<
          _$FrigateScanOutcome_DisconnectedImpl>
      get copyWith => __$$FrigateScanOutcome_DisconnectedImplCopyWithImpl<
          _$FrigateScanOutcome_DisconnectedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() completed,
    required TResult Function(String reason) disconnected,
  }) {
    return disconnected(reason);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? completed,
    TResult? Function(String reason)? disconnected,
  }) {
    return disconnected?.call(reason);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? completed,
    TResult Function(String reason)? disconnected,
    required TResult orElse(),
  }) {
    if (disconnected != null) {
      return disconnected(reason);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(FrigateScanOutcome_Completed value) completed,
    required TResult Function(FrigateScanOutcome_Disconnected value)
        disconnected,
  }) {
    return disconnected(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(FrigateScanOutcome_Completed value)? completed,
    TResult? Function(FrigateScanOutcome_Disconnected value)? disconnected,
  }) {
    return disconnected?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(FrigateScanOutcome_Completed value)? completed,
    TResult Function(FrigateScanOutcome_Disconnected value)? disconnected,
    required TResult orElse(),
  }) {
    if (disconnected != null) {
      return disconnected(this);
    }
    return orElse();
  }
}

abstract class FrigateScanOutcome_Disconnected extends FrigateScanOutcome {
  const factory FrigateScanOutcome_Disconnected(
      {required final String reason}) = _$FrigateScanOutcome_DisconnectedImpl;
  const FrigateScanOutcome_Disconnected._() : super._();

  String get reason;

  /// Create a copy of FrigateScanOutcome
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FrigateScanOutcome_DisconnectedImplCopyWith<
          _$FrigateScanOutcome_DisconnectedImpl>
      get copyWith => throw _privateConstructorUsedError;
}
