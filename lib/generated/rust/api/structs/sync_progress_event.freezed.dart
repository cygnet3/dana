// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_progress_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$SyncProgressEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int field0) height,
    required TResult Function(int height) tip,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int field0)? height,
    TResult? Function(int height)? tip,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int field0)? height,
    TResult Function(int height)? tip,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SyncProgressEvent_Height value) height,
    required TResult Function(SyncProgressEvent_Tip value) tip,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SyncProgressEvent_Height value)? height,
    TResult? Function(SyncProgressEvent_Tip value)? tip,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SyncProgressEvent_Height value)? height,
    TResult Function(SyncProgressEvent_Tip value)? tip,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncProgressEventCopyWith<$Res> {
  factory $SyncProgressEventCopyWith(
          SyncProgressEvent value, $Res Function(SyncProgressEvent) then) =
      _$SyncProgressEventCopyWithImpl<$Res, SyncProgressEvent>;
}

/// @nodoc
class _$SyncProgressEventCopyWithImpl<$Res, $Val extends SyncProgressEvent>
    implements $SyncProgressEventCopyWith<$Res> {
  _$SyncProgressEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$SyncProgressEvent_HeightImplCopyWith<$Res> {
  factory _$$SyncProgressEvent_HeightImplCopyWith(
          _$SyncProgressEvent_HeightImpl value,
          $Res Function(_$SyncProgressEvent_HeightImpl) then) =
      __$$SyncProgressEvent_HeightImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int field0});
}

/// @nodoc
class __$$SyncProgressEvent_HeightImplCopyWithImpl<$Res>
    extends _$SyncProgressEventCopyWithImpl<$Res,
        _$SyncProgressEvent_HeightImpl>
    implements _$$SyncProgressEvent_HeightImplCopyWith<$Res> {
  __$$SyncProgressEvent_HeightImplCopyWithImpl(
      _$SyncProgressEvent_HeightImpl _value,
      $Res Function(_$SyncProgressEvent_HeightImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$SyncProgressEvent_HeightImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$SyncProgressEvent_HeightImpl extends SyncProgressEvent_Height {
  const _$SyncProgressEvent_HeightImpl(this.field0) : super._();

  @override
  final int field0;

  @override
  String toString() {
    return 'SyncProgressEvent.height(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncProgressEvent_HeightImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncProgressEvent_HeightImplCopyWith<_$SyncProgressEvent_HeightImpl>
      get copyWith => __$$SyncProgressEvent_HeightImplCopyWithImpl<
          _$SyncProgressEvent_HeightImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int field0) height,
    required TResult Function(int height) tip,
  }) {
    return height(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int field0)? height,
    TResult? Function(int height)? tip,
  }) {
    return height?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int field0)? height,
    TResult Function(int height)? tip,
    required TResult orElse(),
  }) {
    if (height != null) {
      return height(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SyncProgressEvent_Height value) height,
    required TResult Function(SyncProgressEvent_Tip value) tip,
  }) {
    return height(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SyncProgressEvent_Height value)? height,
    TResult? Function(SyncProgressEvent_Tip value)? tip,
  }) {
    return height?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SyncProgressEvent_Height value)? height,
    TResult Function(SyncProgressEvent_Tip value)? tip,
    required TResult orElse(),
  }) {
    if (height != null) {
      return height(this);
    }
    return orElse();
  }
}

abstract class SyncProgressEvent_Height extends SyncProgressEvent {
  const factory SyncProgressEvent_Height(final int field0) =
      _$SyncProgressEvent_HeightImpl;
  const SyncProgressEvent_Height._() : super._();

  int get field0;

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncProgressEvent_HeightImplCopyWith<_$SyncProgressEvent_HeightImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SyncProgressEvent_TipImplCopyWith<$Res> {
  factory _$$SyncProgressEvent_TipImplCopyWith(
          _$SyncProgressEvent_TipImpl value,
          $Res Function(_$SyncProgressEvent_TipImpl) then) =
      __$$SyncProgressEvent_TipImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int height});
}

/// @nodoc
class __$$SyncProgressEvent_TipImplCopyWithImpl<$Res>
    extends _$SyncProgressEventCopyWithImpl<$Res, _$SyncProgressEvent_TipImpl>
    implements _$$SyncProgressEvent_TipImplCopyWith<$Res> {
  __$$SyncProgressEvent_TipImplCopyWithImpl(_$SyncProgressEvent_TipImpl _value,
      $Res Function(_$SyncProgressEvent_TipImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? height = null,
  }) {
    return _then(_$SyncProgressEvent_TipImpl(
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$SyncProgressEvent_TipImpl extends SyncProgressEvent_Tip {
  const _$SyncProgressEvent_TipImpl({required this.height}) : super._();

  @override
  final int height;

  @override
  String toString() {
    return 'SyncProgressEvent.tip(height: $height)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncProgressEvent_TipImpl &&
            (identical(other.height, height) || other.height == height));
  }

  @override
  int get hashCode => Object.hash(runtimeType, height);

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncProgressEvent_TipImplCopyWith<_$SyncProgressEvent_TipImpl>
      get copyWith => __$$SyncProgressEvent_TipImplCopyWithImpl<
          _$SyncProgressEvent_TipImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int field0) height,
    required TResult Function(int height) tip,
  }) {
    return tip(this.height);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int field0)? height,
    TResult? Function(int height)? tip,
  }) {
    return tip?.call(this.height);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int field0)? height,
    TResult Function(int height)? tip,
    required TResult orElse(),
  }) {
    if (tip != null) {
      return tip(this.height);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SyncProgressEvent_Height value) height,
    required TResult Function(SyncProgressEvent_Tip value) tip,
  }) {
    return tip(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SyncProgressEvent_Height value)? height,
    TResult? Function(SyncProgressEvent_Tip value)? tip,
  }) {
    return tip?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SyncProgressEvent_Height value)? height,
    TResult Function(SyncProgressEvent_Tip value)? tip,
    required TResult orElse(),
  }) {
    if (tip != null) {
      return tip(this);
    }
    return orElse();
  }
}

abstract class SyncProgressEvent_Tip extends SyncProgressEvent {
  const factory SyncProgressEvent_Tip({required final int height}) =
      _$SyncProgressEvent_TipImpl;
  const SyncProgressEvent_Tip._() : super._();

  int get height;

  /// Create a copy of SyncProgressEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncProgressEvent_TipImplCopyWith<_$SyncProgressEvent_TipImpl>
      get copyWith => throw _privateConstructorUsedError;
}
