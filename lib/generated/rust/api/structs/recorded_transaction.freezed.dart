// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recorded_transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ApiRecordedTransaction {
  Object get field0 => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ApiRecordedTransactionIncoming field0) incoming,
    required TResult Function(ApiRecordedTransactionOutgoing field0) outgoing,
    required TResult Function(ApiRecordedTransactionUnknownOutgoing field0)
        unknownOutgoing,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult? Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult? Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ApiRecordedTransaction_Incoming value) incoming,
    required TResult Function(ApiRecordedTransaction_Outgoing value) outgoing,
    required TResult Function(ApiRecordedTransaction_UnknownOutgoing value)
        unknownOutgoing,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult? Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult? Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ApiRecordedTransactionCopyWith<$Res> {
  factory $ApiRecordedTransactionCopyWith(ApiRecordedTransaction value,
          $Res Function(ApiRecordedTransaction) then) =
      _$ApiRecordedTransactionCopyWithImpl<$Res, ApiRecordedTransaction>;
}

/// @nodoc
class _$ApiRecordedTransactionCopyWithImpl<$Res,
        $Val extends ApiRecordedTransaction>
    implements $ApiRecordedTransactionCopyWith<$Res> {
  _$ApiRecordedTransactionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$ApiRecordedTransaction_IncomingImplCopyWith<$Res> {
  factory _$$ApiRecordedTransaction_IncomingImplCopyWith(
          _$ApiRecordedTransaction_IncomingImpl value,
          $Res Function(_$ApiRecordedTransaction_IncomingImpl) then) =
      __$$ApiRecordedTransaction_IncomingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ApiRecordedTransactionIncoming field0});
}

/// @nodoc
class __$$ApiRecordedTransaction_IncomingImplCopyWithImpl<$Res>
    extends _$ApiRecordedTransactionCopyWithImpl<$Res,
        _$ApiRecordedTransaction_IncomingImpl>
    implements _$$ApiRecordedTransaction_IncomingImplCopyWith<$Res> {
  __$$ApiRecordedTransaction_IncomingImplCopyWithImpl(
      _$ApiRecordedTransaction_IncomingImpl _value,
      $Res Function(_$ApiRecordedTransaction_IncomingImpl) _then)
      : super(_value, _then);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ApiRecordedTransaction_IncomingImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as ApiRecordedTransactionIncoming,
    ));
  }
}

/// @nodoc

class _$ApiRecordedTransaction_IncomingImpl
    extends ApiRecordedTransaction_Incoming {
  const _$ApiRecordedTransaction_IncomingImpl(this.field0) : super._();

  @override
  final ApiRecordedTransactionIncoming field0;

  @override
  String toString() {
    return 'ApiRecordedTransaction.incoming(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiRecordedTransaction_IncomingImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiRecordedTransaction_IncomingImplCopyWith<
          _$ApiRecordedTransaction_IncomingImpl>
      get copyWith => __$$ApiRecordedTransaction_IncomingImplCopyWithImpl<
          _$ApiRecordedTransaction_IncomingImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ApiRecordedTransactionIncoming field0) incoming,
    required TResult Function(ApiRecordedTransactionOutgoing field0) outgoing,
    required TResult Function(ApiRecordedTransactionUnknownOutgoing field0)
        unknownOutgoing,
  }) {
    return incoming(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult? Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult? Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
  }) {
    return incoming?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (incoming != null) {
      return incoming(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ApiRecordedTransaction_Incoming value) incoming,
    required TResult Function(ApiRecordedTransaction_Outgoing value) outgoing,
    required TResult Function(ApiRecordedTransaction_UnknownOutgoing value)
        unknownOutgoing,
  }) {
    return incoming(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult? Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult? Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
  }) {
    return incoming?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (incoming != null) {
      return incoming(this);
    }
    return orElse();
  }
}

abstract class ApiRecordedTransaction_Incoming extends ApiRecordedTransaction {
  const factory ApiRecordedTransaction_Incoming(
          final ApiRecordedTransactionIncoming field0) =
      _$ApiRecordedTransaction_IncomingImpl;
  const ApiRecordedTransaction_Incoming._() : super._();

  @override
  ApiRecordedTransactionIncoming get field0;

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ApiRecordedTransaction_IncomingImplCopyWith<
          _$ApiRecordedTransaction_IncomingImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ApiRecordedTransaction_OutgoingImplCopyWith<$Res> {
  factory _$$ApiRecordedTransaction_OutgoingImplCopyWith(
          _$ApiRecordedTransaction_OutgoingImpl value,
          $Res Function(_$ApiRecordedTransaction_OutgoingImpl) then) =
      __$$ApiRecordedTransaction_OutgoingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ApiRecordedTransactionOutgoing field0});
}

/// @nodoc
class __$$ApiRecordedTransaction_OutgoingImplCopyWithImpl<$Res>
    extends _$ApiRecordedTransactionCopyWithImpl<$Res,
        _$ApiRecordedTransaction_OutgoingImpl>
    implements _$$ApiRecordedTransaction_OutgoingImplCopyWith<$Res> {
  __$$ApiRecordedTransaction_OutgoingImplCopyWithImpl(
      _$ApiRecordedTransaction_OutgoingImpl _value,
      $Res Function(_$ApiRecordedTransaction_OutgoingImpl) _then)
      : super(_value, _then);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ApiRecordedTransaction_OutgoingImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as ApiRecordedTransactionOutgoing,
    ));
  }
}

/// @nodoc

class _$ApiRecordedTransaction_OutgoingImpl
    extends ApiRecordedTransaction_Outgoing {
  const _$ApiRecordedTransaction_OutgoingImpl(this.field0) : super._();

  @override
  final ApiRecordedTransactionOutgoing field0;

  @override
  String toString() {
    return 'ApiRecordedTransaction.outgoing(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiRecordedTransaction_OutgoingImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiRecordedTransaction_OutgoingImplCopyWith<
          _$ApiRecordedTransaction_OutgoingImpl>
      get copyWith => __$$ApiRecordedTransaction_OutgoingImplCopyWithImpl<
          _$ApiRecordedTransaction_OutgoingImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ApiRecordedTransactionIncoming field0) incoming,
    required TResult Function(ApiRecordedTransactionOutgoing field0) outgoing,
    required TResult Function(ApiRecordedTransactionUnknownOutgoing field0)
        unknownOutgoing,
  }) {
    return outgoing(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult? Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult? Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
  }) {
    return outgoing?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (outgoing != null) {
      return outgoing(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ApiRecordedTransaction_Incoming value) incoming,
    required TResult Function(ApiRecordedTransaction_Outgoing value) outgoing,
    required TResult Function(ApiRecordedTransaction_UnknownOutgoing value)
        unknownOutgoing,
  }) {
    return outgoing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult? Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult? Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
  }) {
    return outgoing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (outgoing != null) {
      return outgoing(this);
    }
    return orElse();
  }
}

abstract class ApiRecordedTransaction_Outgoing extends ApiRecordedTransaction {
  const factory ApiRecordedTransaction_Outgoing(
          final ApiRecordedTransactionOutgoing field0) =
      _$ApiRecordedTransaction_OutgoingImpl;
  const ApiRecordedTransaction_Outgoing._() : super._();

  @override
  ApiRecordedTransactionOutgoing get field0;

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ApiRecordedTransaction_OutgoingImplCopyWith<
          _$ApiRecordedTransaction_OutgoingImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ApiRecordedTransaction_UnknownOutgoingImplCopyWith<$Res> {
  factory _$$ApiRecordedTransaction_UnknownOutgoingImplCopyWith(
          _$ApiRecordedTransaction_UnknownOutgoingImpl value,
          $Res Function(_$ApiRecordedTransaction_UnknownOutgoingImpl) then) =
      __$$ApiRecordedTransaction_UnknownOutgoingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ApiRecordedTransactionUnknownOutgoing field0});
}

/// @nodoc
class __$$ApiRecordedTransaction_UnknownOutgoingImplCopyWithImpl<$Res>
    extends _$ApiRecordedTransactionCopyWithImpl<$Res,
        _$ApiRecordedTransaction_UnknownOutgoingImpl>
    implements _$$ApiRecordedTransaction_UnknownOutgoingImplCopyWith<$Res> {
  __$$ApiRecordedTransaction_UnknownOutgoingImplCopyWithImpl(
      _$ApiRecordedTransaction_UnknownOutgoingImpl _value,
      $Res Function(_$ApiRecordedTransaction_UnknownOutgoingImpl) _then)
      : super(_value, _then);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ApiRecordedTransaction_UnknownOutgoingImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as ApiRecordedTransactionUnknownOutgoing,
    ));
  }
}

/// @nodoc

class _$ApiRecordedTransaction_UnknownOutgoingImpl
    extends ApiRecordedTransaction_UnknownOutgoing {
  const _$ApiRecordedTransaction_UnknownOutgoingImpl(this.field0) : super._();

  @override
  final ApiRecordedTransactionUnknownOutgoing field0;

  @override
  String toString() {
    return 'ApiRecordedTransaction.unknownOutgoing(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiRecordedTransaction_UnknownOutgoingImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiRecordedTransaction_UnknownOutgoingImplCopyWith<
          _$ApiRecordedTransaction_UnknownOutgoingImpl>
      get copyWith =>
          __$$ApiRecordedTransaction_UnknownOutgoingImplCopyWithImpl<
              _$ApiRecordedTransaction_UnknownOutgoingImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ApiRecordedTransactionIncoming field0) incoming,
    required TResult Function(ApiRecordedTransactionOutgoing field0) outgoing,
    required TResult Function(ApiRecordedTransactionUnknownOutgoing field0)
        unknownOutgoing,
  }) {
    return unknownOutgoing(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult? Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult? Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
  }) {
    return unknownOutgoing?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ApiRecordedTransactionIncoming field0)? incoming,
    TResult Function(ApiRecordedTransactionOutgoing field0)? outgoing,
    TResult Function(ApiRecordedTransactionUnknownOutgoing field0)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (unknownOutgoing != null) {
      return unknownOutgoing(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ApiRecordedTransaction_Incoming value) incoming,
    required TResult Function(ApiRecordedTransaction_Outgoing value) outgoing,
    required TResult Function(ApiRecordedTransaction_UnknownOutgoing value)
        unknownOutgoing,
  }) {
    return unknownOutgoing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult? Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult? Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
  }) {
    return unknownOutgoing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ApiRecordedTransaction_Incoming value)? incoming,
    TResult Function(ApiRecordedTransaction_Outgoing value)? outgoing,
    TResult Function(ApiRecordedTransaction_UnknownOutgoing value)?
        unknownOutgoing,
    required TResult orElse(),
  }) {
    if (unknownOutgoing != null) {
      return unknownOutgoing(this);
    }
    return orElse();
  }
}

abstract class ApiRecordedTransaction_UnknownOutgoing
    extends ApiRecordedTransaction {
  const factory ApiRecordedTransaction_UnknownOutgoing(
          final ApiRecordedTransactionUnknownOutgoing field0) =
      _$ApiRecordedTransaction_UnknownOutgoingImpl;
  const ApiRecordedTransaction_UnknownOutgoing._() : super._();

  @override
  ApiRecordedTransactionUnknownOutgoing get field0;

  /// Create a copy of ApiRecordedTransaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ApiRecordedTransaction_UnknownOutgoingImplCopyWith<
          _$ApiRecordedTransaction_UnknownOutgoingImpl>
      get copyWith => throw _privateConstructorUsedError;
}
