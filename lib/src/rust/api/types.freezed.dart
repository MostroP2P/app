// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$InvoiceVerdict {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InvoiceVerdictCopyWith<$Res> {
  factory $InvoiceVerdictCopyWith(
    InvoiceVerdict value,
    $Res Function(InvoiceVerdict) then,
  ) = _$InvoiceVerdictCopyWithImpl<$Res, InvoiceVerdict>;
}

/// @nodoc
class _$InvoiceVerdictCopyWithImpl<$Res, $Val extends InvoiceVerdict>
    implements $InvoiceVerdictCopyWith<$Res> {
  _$InvoiceVerdictCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$InvoiceVerdict_EmptyImplCopyWith<$Res> {
  factory _$$InvoiceVerdict_EmptyImplCopyWith(
    _$InvoiceVerdict_EmptyImpl value,
    $Res Function(_$InvoiceVerdict_EmptyImpl) then,
  ) = __$$InvoiceVerdict_EmptyImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$InvoiceVerdict_EmptyImplCopyWithImpl<$Res>
    extends _$InvoiceVerdictCopyWithImpl<$Res, _$InvoiceVerdict_EmptyImpl>
    implements _$$InvoiceVerdict_EmptyImplCopyWith<$Res> {
  __$$InvoiceVerdict_EmptyImplCopyWithImpl(
    _$InvoiceVerdict_EmptyImpl _value,
    $Res Function(_$InvoiceVerdict_EmptyImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InvoiceVerdict_EmptyImpl extends InvoiceVerdict_Empty {
  const _$InvoiceVerdict_EmptyImpl() : super._();

  @override
  String toString() {
    return 'InvoiceVerdict.empty()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvoiceVerdict_EmptyImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) {
    return empty();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) {
    return empty?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) {
    return empty(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) {
    return empty?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty(this);
    }
    return orElse();
  }
}

abstract class InvoiceVerdict_Empty extends InvoiceVerdict {
  const factory InvoiceVerdict_Empty() = _$InvoiceVerdict_EmptyImpl;
  const InvoiceVerdict_Empty._() : super._();
}

/// @nodoc
abstract class _$$InvoiceVerdict_UnverifiedImplCopyWith<$Res> {
  factory _$$InvoiceVerdict_UnverifiedImplCopyWith(
    _$InvoiceVerdict_UnverifiedImpl value,
    $Res Function(_$InvoiceVerdict_UnverifiedImpl) then,
  ) = __$$InvoiceVerdict_UnverifiedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$InvoiceVerdict_UnverifiedImplCopyWithImpl<$Res>
    extends _$InvoiceVerdictCopyWithImpl<$Res, _$InvoiceVerdict_UnverifiedImpl>
    implements _$$InvoiceVerdict_UnverifiedImplCopyWith<$Res> {
  __$$InvoiceVerdict_UnverifiedImplCopyWithImpl(
    _$InvoiceVerdict_UnverifiedImpl _value,
    $Res Function(_$InvoiceVerdict_UnverifiedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InvoiceVerdict_UnverifiedImpl extends InvoiceVerdict_Unverified {
  const _$InvoiceVerdict_UnverifiedImpl() : super._();

  @override
  String toString() {
    return 'InvoiceVerdict.unverified()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvoiceVerdict_UnverifiedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) {
    return unverified();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) {
    return unverified?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) {
    if (unverified != null) {
      return unverified();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) {
    return unverified(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) {
    return unverified?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) {
    if (unverified != null) {
      return unverified(this);
    }
    return orElse();
  }
}

abstract class InvoiceVerdict_Unverified extends InvoiceVerdict {
  const factory InvoiceVerdict_Unverified() = _$InvoiceVerdict_UnverifiedImpl;
  const InvoiceVerdict_Unverified._() : super._();
}

/// @nodoc
abstract class _$$InvoiceVerdict_AddressImplCopyWith<$Res> {
  factory _$$InvoiceVerdict_AddressImplCopyWith(
    _$InvoiceVerdict_AddressImpl value,
    $Res Function(_$InvoiceVerdict_AddressImpl) then,
  ) = __$$InvoiceVerdict_AddressImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$InvoiceVerdict_AddressImplCopyWithImpl<$Res>
    extends _$InvoiceVerdictCopyWithImpl<$Res, _$InvoiceVerdict_AddressImpl>
    implements _$$InvoiceVerdict_AddressImplCopyWith<$Res> {
  __$$InvoiceVerdict_AddressImplCopyWithImpl(
    _$InvoiceVerdict_AddressImpl _value,
    $Res Function(_$InvoiceVerdict_AddressImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InvoiceVerdict_AddressImpl extends InvoiceVerdict_Address {
  const _$InvoiceVerdict_AddressImpl() : super._();

  @override
  String toString() {
    return 'InvoiceVerdict.address()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvoiceVerdict_AddressImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) {
    return address();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) {
    return address?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) {
    if (address != null) {
      return address();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) {
    return address(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) {
    return address?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) {
    if (address != null) {
      return address(this);
    }
    return orElse();
  }
}

abstract class InvoiceVerdict_Address extends InvoiceVerdict {
  const factory InvoiceVerdict_Address() = _$InvoiceVerdict_AddressImpl;
  const InvoiceVerdict_Address._() : super._();
}

/// @nodoc
abstract class _$$InvoiceVerdict_ValidImplCopyWith<$Res> {
  factory _$$InvoiceVerdict_ValidImplCopyWith(
    _$InvoiceVerdict_ValidImpl value,
    $Res Function(_$InvoiceVerdict_ValidImpl) then,
  ) = __$$InvoiceVerdict_ValidImplCopyWithImpl<$Res>;
  @useResult
  $Res call({BigInt sats, BigInt expiresAt});
}

/// @nodoc
class __$$InvoiceVerdict_ValidImplCopyWithImpl<$Res>
    extends _$InvoiceVerdictCopyWithImpl<$Res, _$InvoiceVerdict_ValidImpl>
    implements _$$InvoiceVerdict_ValidImplCopyWith<$Res> {
  __$$InvoiceVerdict_ValidImplCopyWithImpl(
    _$InvoiceVerdict_ValidImpl _value,
    $Res Function(_$InvoiceVerdict_ValidImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? sats = null, Object? expiresAt = null}) {
    return _then(
      _$InvoiceVerdict_ValidImpl(
        sats:
            null == sats
                ? _value.sats
                : sats // ignore: cast_nullable_to_non_nullable
                    as BigInt,
        expiresAt:
            null == expiresAt
                ? _value.expiresAt
                : expiresAt // ignore: cast_nullable_to_non_nullable
                    as BigInt,
      ),
    );
  }
}

/// @nodoc

class _$InvoiceVerdict_ValidImpl extends InvoiceVerdict_Valid {
  const _$InvoiceVerdict_ValidImpl({
    required this.sats,
    required this.expiresAt,
  }) : super._();

  @override
  final BigInt sats;
  @override
  final BigInt expiresAt;

  @override
  String toString() {
    return 'InvoiceVerdict.valid(sats: $sats, expiresAt: $expiresAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvoiceVerdict_ValidImpl &&
            (identical(other.sats, sats) || other.sats == sats) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt));
  }

  @override
  int get hashCode => Object.hash(runtimeType, sats, expiresAt);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InvoiceVerdict_ValidImplCopyWith<_$InvoiceVerdict_ValidImpl>
  get copyWith =>
      __$$InvoiceVerdict_ValidImplCopyWithImpl<_$InvoiceVerdict_ValidImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) {
    return valid(sats, expiresAt);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) {
    return valid?.call(sats, expiresAt);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) {
    if (valid != null) {
      return valid(sats, expiresAt);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) {
    return valid(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) {
    return valid?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) {
    if (valid != null) {
      return valid(this);
    }
    return orElse();
  }
}

abstract class InvoiceVerdict_Valid extends InvoiceVerdict {
  const factory InvoiceVerdict_Valid({
    required final BigInt sats,
    required final BigInt expiresAt,
  }) = _$InvoiceVerdict_ValidImpl;
  const InvoiceVerdict_Valid._() : super._();

  BigInt get sats;
  BigInt get expiresAt;

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InvoiceVerdict_ValidImplCopyWith<_$InvoiceVerdict_ValidImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$InvoiceVerdict_RejectedImplCopyWith<$Res> {
  factory _$$InvoiceVerdict_RejectedImplCopyWith(
    _$InvoiceVerdict_RejectedImpl value,
    $Res Function(_$InvoiceVerdict_RejectedImpl) then,
  ) = __$$InvoiceVerdict_RejectedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({
    InvoiceProblem problem,
    BigInt? actualMsat,
    BigInt? expectedSats,
    String? invoiceNetwork,
    String? nodeNetwork,
    BigInt? minRemainingSecs,
  });
}

/// @nodoc
class __$$InvoiceVerdict_RejectedImplCopyWithImpl<$Res>
    extends _$InvoiceVerdictCopyWithImpl<$Res, _$InvoiceVerdict_RejectedImpl>
    implements _$$InvoiceVerdict_RejectedImplCopyWith<$Res> {
  __$$InvoiceVerdict_RejectedImplCopyWithImpl(
    _$InvoiceVerdict_RejectedImpl _value,
    $Res Function(_$InvoiceVerdict_RejectedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? problem = null,
    Object? actualMsat = freezed,
    Object? expectedSats = freezed,
    Object? invoiceNetwork = freezed,
    Object? nodeNetwork = freezed,
    Object? minRemainingSecs = freezed,
  }) {
    return _then(
      _$InvoiceVerdict_RejectedImpl(
        problem:
            null == problem
                ? _value.problem
                : problem // ignore: cast_nullable_to_non_nullable
                    as InvoiceProblem,
        actualMsat:
            freezed == actualMsat
                ? _value.actualMsat
                : actualMsat // ignore: cast_nullable_to_non_nullable
                    as BigInt?,
        expectedSats:
            freezed == expectedSats
                ? _value.expectedSats
                : expectedSats // ignore: cast_nullable_to_non_nullable
                    as BigInt?,
        invoiceNetwork:
            freezed == invoiceNetwork
                ? _value.invoiceNetwork
                : invoiceNetwork // ignore: cast_nullable_to_non_nullable
                    as String?,
        nodeNetwork:
            freezed == nodeNetwork
                ? _value.nodeNetwork
                : nodeNetwork // ignore: cast_nullable_to_non_nullable
                    as String?,
        minRemainingSecs:
            freezed == minRemainingSecs
                ? _value.minRemainingSecs
                : minRemainingSecs // ignore: cast_nullable_to_non_nullable
                    as BigInt?,
      ),
    );
  }
}

/// @nodoc

class _$InvoiceVerdict_RejectedImpl extends InvoiceVerdict_Rejected {
  const _$InvoiceVerdict_RejectedImpl({
    required this.problem,
    this.actualMsat,
    this.expectedSats,
    this.invoiceNetwork,
    this.nodeNetwork,
    this.minRemainingSecs,
  }) : super._();

  @override
  final InvoiceProblem problem;

  /// `WrongAmount`: what the invoice asks for, in msat (a sub-sat
  /// remainder must not be rounded into a match).
  @override
  final BigInt? actualMsat;

  /// `WrongAmount`: what the trade pays.
  @override
  final BigInt? expectedSats;

  /// `WrongNetwork`: the invoice's chain, in LND naming.
  @override
  final String? invoiceNetwork;

  /// `WrongNetwork`: the node's chain, in LND naming.
  @override
  final String? nodeNetwork;

  /// `ExpiresTooSoon`: the node's minimum remaining lifetime, seconds.
  @override
  final BigInt? minRemainingSecs;

  @override
  String toString() {
    return 'InvoiceVerdict.rejected(problem: $problem, actualMsat: $actualMsat, expectedSats: $expectedSats, invoiceNetwork: $invoiceNetwork, nodeNetwork: $nodeNetwork, minRemainingSecs: $minRemainingSecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvoiceVerdict_RejectedImpl &&
            (identical(other.problem, problem) || other.problem == problem) &&
            (identical(other.actualMsat, actualMsat) ||
                other.actualMsat == actualMsat) &&
            (identical(other.expectedSats, expectedSats) ||
                other.expectedSats == expectedSats) &&
            (identical(other.invoiceNetwork, invoiceNetwork) ||
                other.invoiceNetwork == invoiceNetwork) &&
            (identical(other.nodeNetwork, nodeNetwork) ||
                other.nodeNetwork == nodeNetwork) &&
            (identical(other.minRemainingSecs, minRemainingSecs) ||
                other.minRemainingSecs == minRemainingSecs));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    problem,
    actualMsat,
    expectedSats,
    invoiceNetwork,
    nodeNetwork,
    minRemainingSecs,
  );

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InvoiceVerdict_RejectedImplCopyWith<_$InvoiceVerdict_RejectedImpl>
  get copyWith => __$$InvoiceVerdict_RejectedImplCopyWithImpl<
    _$InvoiceVerdict_RejectedImpl
  >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function() unverified,
    required TResult Function() address,
    required TResult Function(BigInt sats, BigInt expiresAt) valid,
    required TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )
    rejected,
  }) {
    return rejected(
      problem,
      actualMsat,
      expectedSats,
      invoiceNetwork,
      nodeNetwork,
      minRemainingSecs,
    );
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function()? unverified,
    TResult? Function()? address,
    TResult? Function(BigInt sats, BigInt expiresAt)? valid,
    TResult? Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
  }) {
    return rejected?.call(
      problem,
      actualMsat,
      expectedSats,
      invoiceNetwork,
      nodeNetwork,
      minRemainingSecs,
    );
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function()? unverified,
    TResult Function()? address,
    TResult Function(BigInt sats, BigInt expiresAt)? valid,
    TResult Function(
      InvoiceProblem problem,
      BigInt? actualMsat,
      BigInt? expectedSats,
      String? invoiceNetwork,
      String? nodeNetwork,
      BigInt? minRemainingSecs,
    )?
    rejected,
    required TResult orElse(),
  }) {
    if (rejected != null) {
      return rejected(
        problem,
        actualMsat,
        expectedSats,
        invoiceNetwork,
        nodeNetwork,
        minRemainingSecs,
      );
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InvoiceVerdict_Empty value) empty,
    required TResult Function(InvoiceVerdict_Unverified value) unverified,
    required TResult Function(InvoiceVerdict_Address value) address,
    required TResult Function(InvoiceVerdict_Valid value) valid,
    required TResult Function(InvoiceVerdict_Rejected value) rejected,
  }) {
    return rejected(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InvoiceVerdict_Empty value)? empty,
    TResult? Function(InvoiceVerdict_Unverified value)? unverified,
    TResult? Function(InvoiceVerdict_Address value)? address,
    TResult? Function(InvoiceVerdict_Valid value)? valid,
    TResult? Function(InvoiceVerdict_Rejected value)? rejected,
  }) {
    return rejected?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InvoiceVerdict_Empty value)? empty,
    TResult Function(InvoiceVerdict_Unverified value)? unverified,
    TResult Function(InvoiceVerdict_Address value)? address,
    TResult Function(InvoiceVerdict_Valid value)? valid,
    TResult Function(InvoiceVerdict_Rejected value)? rejected,
    required TResult orElse(),
  }) {
    if (rejected != null) {
      return rejected(this);
    }
    return orElse();
  }
}

abstract class InvoiceVerdict_Rejected extends InvoiceVerdict {
  const factory InvoiceVerdict_Rejected({
    required final InvoiceProblem problem,
    final BigInt? actualMsat,
    final BigInt? expectedSats,
    final String? invoiceNetwork,
    final String? nodeNetwork,
    final BigInt? minRemainingSecs,
  }) = _$InvoiceVerdict_RejectedImpl;
  const InvoiceVerdict_Rejected._() : super._();

  InvoiceProblem get problem;

  /// `WrongAmount`: what the invoice asks for, in msat (a sub-sat
  /// remainder must not be rounded into a match).
  BigInt? get actualMsat;

  /// `WrongAmount`: what the trade pays.
  BigInt? get expectedSats;

  /// `WrongNetwork`: the invoice's chain, in LND naming.
  String? get invoiceNetwork;

  /// `WrongNetwork`: the node's chain, in LND naming.
  String? get nodeNetwork;

  /// `ExpiresTooSoon`: the node's minimum remaining lifetime, seconds.
  BigInt? get minRemainingSecs;

  /// Create a copy of InvoiceVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InvoiceVerdict_RejectedImplCopyWith<_$InvoiceVerdict_RejectedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$OrderDelta {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int revision, OrderInfo order) upserted,
    required TResult Function(int revision, String orderId) removed,
    required TResult Function() resync,
    required TResult Function() loaded,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int revision, OrderInfo order)? upserted,
    TResult? Function(int revision, String orderId)? removed,
    TResult? Function()? resync,
    TResult? Function()? loaded,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int revision, OrderInfo order)? upserted,
    TResult Function(int revision, String orderId)? removed,
    TResult Function()? resync,
    TResult Function()? loaded,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OrderDelta_Upserted value) upserted,
    required TResult Function(OrderDelta_Removed value) removed,
    required TResult Function(OrderDelta_Resync value) resync,
    required TResult Function(OrderDelta_Loaded value) loaded,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OrderDelta_Upserted value)? upserted,
    TResult? Function(OrderDelta_Removed value)? removed,
    TResult? Function(OrderDelta_Resync value)? resync,
    TResult? Function(OrderDelta_Loaded value)? loaded,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OrderDelta_Upserted value)? upserted,
    TResult Function(OrderDelta_Removed value)? removed,
    TResult Function(OrderDelta_Resync value)? resync,
    TResult Function(OrderDelta_Loaded value)? loaded,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderDeltaCopyWith<$Res> {
  factory $OrderDeltaCopyWith(
    OrderDelta value,
    $Res Function(OrderDelta) then,
  ) = _$OrderDeltaCopyWithImpl<$Res, OrderDelta>;
}

/// @nodoc
class _$OrderDeltaCopyWithImpl<$Res, $Val extends OrderDelta>
    implements $OrderDeltaCopyWith<$Res> {
  _$OrderDeltaCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$OrderDelta_UpsertedImplCopyWith<$Res> {
  factory _$$OrderDelta_UpsertedImplCopyWith(
    _$OrderDelta_UpsertedImpl value,
    $Res Function(_$OrderDelta_UpsertedImpl) then,
  ) = __$$OrderDelta_UpsertedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int revision, OrderInfo order});
}

/// @nodoc
class __$$OrderDelta_UpsertedImplCopyWithImpl<$Res>
    extends _$OrderDeltaCopyWithImpl<$Res, _$OrderDelta_UpsertedImpl>
    implements _$$OrderDelta_UpsertedImplCopyWith<$Res> {
  __$$OrderDelta_UpsertedImplCopyWithImpl(
    _$OrderDelta_UpsertedImpl _value,
    $Res Function(_$OrderDelta_UpsertedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? revision = null, Object? order = null}) {
    return _then(
      _$OrderDelta_UpsertedImpl(
        revision:
            null == revision
                ? _value.revision
                : revision // ignore: cast_nullable_to_non_nullable
                    as int,
        order:
            null == order
                ? _value.order
                : order // ignore: cast_nullable_to_non_nullable
                    as OrderInfo,
      ),
    );
  }
}

/// @nodoc

class _$OrderDelta_UpsertedImpl extends OrderDelta_Upserted {
  const _$OrderDelta_UpsertedImpl({required this.revision, required this.order})
    : super._();

  @override
  final int revision;
  @override
  final OrderInfo order;

  @override
  String toString() {
    return 'OrderDelta.upserted(revision: $revision, order: $order)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderDelta_UpsertedImpl &&
            (identical(other.revision, revision) ||
                other.revision == revision) &&
            (identical(other.order, order) || other.order == order));
  }

  @override
  int get hashCode => Object.hash(runtimeType, revision, order);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderDelta_UpsertedImplCopyWith<_$OrderDelta_UpsertedImpl> get copyWith =>
      __$$OrderDelta_UpsertedImplCopyWithImpl<_$OrderDelta_UpsertedImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int revision, OrderInfo order) upserted,
    required TResult Function(int revision, String orderId) removed,
    required TResult Function() resync,
    required TResult Function() loaded,
  }) {
    return upserted(revision, order);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int revision, OrderInfo order)? upserted,
    TResult? Function(int revision, String orderId)? removed,
    TResult? Function()? resync,
    TResult? Function()? loaded,
  }) {
    return upserted?.call(revision, order);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int revision, OrderInfo order)? upserted,
    TResult Function(int revision, String orderId)? removed,
    TResult Function()? resync,
    TResult Function()? loaded,
    required TResult orElse(),
  }) {
    if (upserted != null) {
      return upserted(revision, order);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OrderDelta_Upserted value) upserted,
    required TResult Function(OrderDelta_Removed value) removed,
    required TResult Function(OrderDelta_Resync value) resync,
    required TResult Function(OrderDelta_Loaded value) loaded,
  }) {
    return upserted(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OrderDelta_Upserted value)? upserted,
    TResult? Function(OrderDelta_Removed value)? removed,
    TResult? Function(OrderDelta_Resync value)? resync,
    TResult? Function(OrderDelta_Loaded value)? loaded,
  }) {
    return upserted?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OrderDelta_Upserted value)? upserted,
    TResult Function(OrderDelta_Removed value)? removed,
    TResult Function(OrderDelta_Resync value)? resync,
    TResult Function(OrderDelta_Loaded value)? loaded,
    required TResult orElse(),
  }) {
    if (upserted != null) {
      return upserted(this);
    }
    return orElse();
  }
}

abstract class OrderDelta_Upserted extends OrderDelta {
  const factory OrderDelta_Upserted({
    required final int revision,
    required final OrderInfo order,
  }) = _$OrderDelta_UpsertedImpl;
  const OrderDelta_Upserted._() : super._();

  int get revision;
  OrderInfo get order;

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderDelta_UpsertedImplCopyWith<_$OrderDelta_UpsertedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$OrderDelta_RemovedImplCopyWith<$Res> {
  factory _$$OrderDelta_RemovedImplCopyWith(
    _$OrderDelta_RemovedImpl value,
    $Res Function(_$OrderDelta_RemovedImpl) then,
  ) = __$$OrderDelta_RemovedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int revision, String orderId});
}

/// @nodoc
class __$$OrderDelta_RemovedImplCopyWithImpl<$Res>
    extends _$OrderDeltaCopyWithImpl<$Res, _$OrderDelta_RemovedImpl>
    implements _$$OrderDelta_RemovedImplCopyWith<$Res> {
  __$$OrderDelta_RemovedImplCopyWithImpl(
    _$OrderDelta_RemovedImpl _value,
    $Res Function(_$OrderDelta_RemovedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? revision = null, Object? orderId = null}) {
    return _then(
      _$OrderDelta_RemovedImpl(
        revision:
            null == revision
                ? _value.revision
                : revision // ignore: cast_nullable_to_non_nullable
                    as int,
        orderId:
            null == orderId
                ? _value.orderId
                : orderId // ignore: cast_nullable_to_non_nullable
                    as String,
      ),
    );
  }
}

/// @nodoc

class _$OrderDelta_RemovedImpl extends OrderDelta_Removed {
  const _$OrderDelta_RemovedImpl({
    required this.revision,
    required this.orderId,
  }) : super._();

  @override
  final int revision;
  @override
  final String orderId;

  @override
  String toString() {
    return 'OrderDelta.removed(revision: $revision, orderId: $orderId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderDelta_RemovedImpl &&
            (identical(other.revision, revision) ||
                other.revision == revision) &&
            (identical(other.orderId, orderId) || other.orderId == orderId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, revision, orderId);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderDelta_RemovedImplCopyWith<_$OrderDelta_RemovedImpl> get copyWith =>
      __$$OrderDelta_RemovedImplCopyWithImpl<_$OrderDelta_RemovedImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int revision, OrderInfo order) upserted,
    required TResult Function(int revision, String orderId) removed,
    required TResult Function() resync,
    required TResult Function() loaded,
  }) {
    return removed(revision, orderId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int revision, OrderInfo order)? upserted,
    TResult? Function(int revision, String orderId)? removed,
    TResult? Function()? resync,
    TResult? Function()? loaded,
  }) {
    return removed?.call(revision, orderId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int revision, OrderInfo order)? upserted,
    TResult Function(int revision, String orderId)? removed,
    TResult Function()? resync,
    TResult Function()? loaded,
    required TResult orElse(),
  }) {
    if (removed != null) {
      return removed(revision, orderId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OrderDelta_Upserted value) upserted,
    required TResult Function(OrderDelta_Removed value) removed,
    required TResult Function(OrderDelta_Resync value) resync,
    required TResult Function(OrderDelta_Loaded value) loaded,
  }) {
    return removed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OrderDelta_Upserted value)? upserted,
    TResult? Function(OrderDelta_Removed value)? removed,
    TResult? Function(OrderDelta_Resync value)? resync,
    TResult? Function(OrderDelta_Loaded value)? loaded,
  }) {
    return removed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OrderDelta_Upserted value)? upserted,
    TResult Function(OrderDelta_Removed value)? removed,
    TResult Function(OrderDelta_Resync value)? resync,
    TResult Function(OrderDelta_Loaded value)? loaded,
    required TResult orElse(),
  }) {
    if (removed != null) {
      return removed(this);
    }
    return orElse();
  }
}

abstract class OrderDelta_Removed extends OrderDelta {
  const factory OrderDelta_Removed({
    required final int revision,
    required final String orderId,
  }) = _$OrderDelta_RemovedImpl;
  const OrderDelta_Removed._() : super._();

  int get revision;
  String get orderId;

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderDelta_RemovedImplCopyWith<_$OrderDelta_RemovedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$OrderDelta_ResyncImplCopyWith<$Res> {
  factory _$$OrderDelta_ResyncImplCopyWith(
    _$OrderDelta_ResyncImpl value,
    $Res Function(_$OrderDelta_ResyncImpl) then,
  ) = __$$OrderDelta_ResyncImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$OrderDelta_ResyncImplCopyWithImpl<$Res>
    extends _$OrderDeltaCopyWithImpl<$Res, _$OrderDelta_ResyncImpl>
    implements _$$OrderDelta_ResyncImplCopyWith<$Res> {
  __$$OrderDelta_ResyncImplCopyWithImpl(
    _$OrderDelta_ResyncImpl _value,
    $Res Function(_$OrderDelta_ResyncImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$OrderDelta_ResyncImpl extends OrderDelta_Resync {
  const _$OrderDelta_ResyncImpl() : super._();

  @override
  String toString() {
    return 'OrderDelta.resync()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$OrderDelta_ResyncImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int revision, OrderInfo order) upserted,
    required TResult Function(int revision, String orderId) removed,
    required TResult Function() resync,
    required TResult Function() loaded,
  }) {
    return resync();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int revision, OrderInfo order)? upserted,
    TResult? Function(int revision, String orderId)? removed,
    TResult? Function()? resync,
    TResult? Function()? loaded,
  }) {
    return resync?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int revision, OrderInfo order)? upserted,
    TResult Function(int revision, String orderId)? removed,
    TResult Function()? resync,
    TResult Function()? loaded,
    required TResult orElse(),
  }) {
    if (resync != null) {
      return resync();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OrderDelta_Upserted value) upserted,
    required TResult Function(OrderDelta_Removed value) removed,
    required TResult Function(OrderDelta_Resync value) resync,
    required TResult Function(OrderDelta_Loaded value) loaded,
  }) {
    return resync(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OrderDelta_Upserted value)? upserted,
    TResult? Function(OrderDelta_Removed value)? removed,
    TResult? Function(OrderDelta_Resync value)? resync,
    TResult? Function(OrderDelta_Loaded value)? loaded,
  }) {
    return resync?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OrderDelta_Upserted value)? upserted,
    TResult Function(OrderDelta_Removed value)? removed,
    TResult Function(OrderDelta_Resync value)? resync,
    TResult Function(OrderDelta_Loaded value)? loaded,
    required TResult orElse(),
  }) {
    if (resync != null) {
      return resync(this);
    }
    return orElse();
  }
}

abstract class OrderDelta_Resync extends OrderDelta {
  const factory OrderDelta_Resync() = _$OrderDelta_ResyncImpl;
  const OrderDelta_Resync._() : super._();
}

/// @nodoc
abstract class _$$OrderDelta_LoadedImplCopyWith<$Res> {
  factory _$$OrderDelta_LoadedImplCopyWith(
    _$OrderDelta_LoadedImpl value,
    $Res Function(_$OrderDelta_LoadedImpl) then,
  ) = __$$OrderDelta_LoadedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$OrderDelta_LoadedImplCopyWithImpl<$Res>
    extends _$OrderDeltaCopyWithImpl<$Res, _$OrderDelta_LoadedImpl>
    implements _$$OrderDelta_LoadedImplCopyWith<$Res> {
  __$$OrderDelta_LoadedImplCopyWithImpl(
    _$OrderDelta_LoadedImpl _value,
    $Res Function(_$OrderDelta_LoadedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OrderDelta
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$OrderDelta_LoadedImpl extends OrderDelta_Loaded {
  const _$OrderDelta_LoadedImpl() : super._();

  @override
  String toString() {
    return 'OrderDelta.loaded()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$OrderDelta_LoadedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int revision, OrderInfo order) upserted,
    required TResult Function(int revision, String orderId) removed,
    required TResult Function() resync,
    required TResult Function() loaded,
  }) {
    return loaded();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int revision, OrderInfo order)? upserted,
    TResult? Function(int revision, String orderId)? removed,
    TResult? Function()? resync,
    TResult? Function()? loaded,
  }) {
    return loaded?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int revision, OrderInfo order)? upserted,
    TResult Function(int revision, String orderId)? removed,
    TResult Function()? resync,
    TResult Function()? loaded,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OrderDelta_Upserted value) upserted,
    required TResult Function(OrderDelta_Removed value) removed,
    required TResult Function(OrderDelta_Resync value) resync,
    required TResult Function(OrderDelta_Loaded value) loaded,
  }) {
    return loaded(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OrderDelta_Upserted value)? upserted,
    TResult? Function(OrderDelta_Removed value)? removed,
    TResult? Function(OrderDelta_Resync value)? resync,
    TResult? Function(OrderDelta_Loaded value)? loaded,
  }) {
    return loaded?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OrderDelta_Upserted value)? upserted,
    TResult Function(OrderDelta_Removed value)? removed,
    TResult Function(OrderDelta_Resync value)? resync,
    TResult Function(OrderDelta_Loaded value)? loaded,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(this);
    }
    return orElse();
  }
}

abstract class OrderDelta_Loaded extends OrderDelta {
  const factory OrderDelta_Loaded() = _$OrderDelta_LoadedImpl;
  const OrderDelta_Loaded._() : super._();
}

/// @nodoc
mixin _$PaymentDestination {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PaymentDestinationCopyWith<$Res> {
  factory $PaymentDestinationCopyWith(
    PaymentDestination value,
    $Res Function(PaymentDestination) then,
  ) = _$PaymentDestinationCopyWithImpl<$Res, PaymentDestination>;
}

/// @nodoc
class _$PaymentDestinationCopyWithImpl<$Res, $Val extends PaymentDestination>
    implements $PaymentDestinationCopyWith<$Res> {
  _$PaymentDestinationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$PaymentDestination_EmptyImplCopyWith<$Res> {
  factory _$$PaymentDestination_EmptyImplCopyWith(
    _$PaymentDestination_EmptyImpl value,
    $Res Function(_$PaymentDestination_EmptyImpl) then,
  ) = __$$PaymentDestination_EmptyImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PaymentDestination_EmptyImplCopyWithImpl<$Res>
    extends
        _$PaymentDestinationCopyWithImpl<$Res, _$PaymentDestination_EmptyImpl>
    implements _$$PaymentDestination_EmptyImplCopyWith<$Res> {
  __$$PaymentDestination_EmptyImplCopyWithImpl(
    _$PaymentDestination_EmptyImpl _value,
    $Res Function(_$PaymentDestination_EmptyImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$PaymentDestination_EmptyImpl extends PaymentDestination_Empty {
  const _$PaymentDestination_EmptyImpl() : super._();

  @override
  String toString() {
    return 'PaymentDestination.empty()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentDestination_EmptyImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) {
    return empty();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) {
    return empty?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) {
    return empty(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) {
    return empty?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty(this);
    }
    return orElse();
  }
}

abstract class PaymentDestination_Empty extends PaymentDestination {
  const factory PaymentDestination_Empty() = _$PaymentDestination_EmptyImpl;
  const PaymentDestination_Empty._() : super._();
}

/// @nodoc
abstract class _$$PaymentDestination_Bolt11ImplCopyWith<$Res> {
  factory _$$PaymentDestination_Bolt11ImplCopyWith(
    _$PaymentDestination_Bolt11Impl value,
    $Res Function(_$PaymentDestination_Bolt11Impl) then,
  ) = __$$PaymentDestination_Bolt11ImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Bolt11Summary field0});
}

/// @nodoc
class __$$PaymentDestination_Bolt11ImplCopyWithImpl<$Res>
    extends
        _$PaymentDestinationCopyWithImpl<$Res, _$PaymentDestination_Bolt11Impl>
    implements _$$PaymentDestination_Bolt11ImplCopyWith<$Res> {
  __$$PaymentDestination_Bolt11ImplCopyWithImpl(
    _$PaymentDestination_Bolt11Impl _value,
    $Res Function(_$PaymentDestination_Bolt11Impl) _then,
  ) : super(_value, _then);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$PaymentDestination_Bolt11Impl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                as Bolt11Summary,
      ),
    );
  }
}

/// @nodoc

class _$PaymentDestination_Bolt11Impl extends PaymentDestination_Bolt11 {
  const _$PaymentDestination_Bolt11Impl(this.field0) : super._();

  @override
  final Bolt11Summary field0;

  @override
  String toString() {
    return 'PaymentDestination.bolt11(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentDestination_Bolt11Impl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PaymentDestination_Bolt11ImplCopyWith<_$PaymentDestination_Bolt11Impl>
  get copyWith => __$$PaymentDestination_Bolt11ImplCopyWithImpl<
    _$PaymentDestination_Bolt11Impl
  >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) {
    return bolt11(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) {
    return bolt11?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) {
    if (bolt11 != null) {
      return bolt11(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) {
    return bolt11(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) {
    return bolt11?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) {
    if (bolt11 != null) {
      return bolt11(this);
    }
    return orElse();
  }
}

abstract class PaymentDestination_Bolt11 extends PaymentDestination {
  const factory PaymentDestination_Bolt11(final Bolt11Summary field0) =
      _$PaymentDestination_Bolt11Impl;
  const PaymentDestination_Bolt11._() : super._();

  Bolt11Summary get field0;

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PaymentDestination_Bolt11ImplCopyWith<_$PaymentDestination_Bolt11Impl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PaymentDestination_MalformedBolt11ImplCopyWith<$Res> {
  factory _$$PaymentDestination_MalformedBolt11ImplCopyWith(
    _$PaymentDestination_MalformedBolt11Impl value,
    $Res Function(_$PaymentDestination_MalformedBolt11Impl) then,
  ) = __$$PaymentDestination_MalformedBolt11ImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PaymentDestination_MalformedBolt11ImplCopyWithImpl<$Res>
    extends
        _$PaymentDestinationCopyWithImpl<
          $Res,
          _$PaymentDestination_MalformedBolt11Impl
        >
    implements _$$PaymentDestination_MalformedBolt11ImplCopyWith<$Res> {
  __$$PaymentDestination_MalformedBolt11ImplCopyWithImpl(
    _$PaymentDestination_MalformedBolt11Impl _value,
    $Res Function(_$PaymentDestination_MalformedBolt11Impl) _then,
  ) : super(_value, _then);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$PaymentDestination_MalformedBolt11Impl
    extends PaymentDestination_MalformedBolt11 {
  const _$PaymentDestination_MalformedBolt11Impl() : super._();

  @override
  String toString() {
    return 'PaymentDestination.malformedBolt11()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentDestination_MalformedBolt11Impl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) {
    return malformedBolt11();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) {
    return malformedBolt11?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) {
    if (malformedBolt11 != null) {
      return malformedBolt11();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) {
    return malformedBolt11(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) {
    return malformedBolt11?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) {
    if (malformedBolt11 != null) {
      return malformedBolt11(this);
    }
    return orElse();
  }
}

abstract class PaymentDestination_MalformedBolt11 extends PaymentDestination {
  const factory PaymentDestination_MalformedBolt11() =
      _$PaymentDestination_MalformedBolt11Impl;
  const PaymentDestination_MalformedBolt11._() : super._();
}

/// @nodoc
abstract class _$$PaymentDestination_LightningAddressImplCopyWith<$Res> {
  factory _$$PaymentDestination_LightningAddressImplCopyWith(
    _$PaymentDestination_LightningAddressImpl value,
    $Res Function(_$PaymentDestination_LightningAddressImpl) then,
  ) = __$$PaymentDestination_LightningAddressImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$PaymentDestination_LightningAddressImplCopyWithImpl<$Res>
    extends
        _$PaymentDestinationCopyWithImpl<
          $Res,
          _$PaymentDestination_LightningAddressImpl
        >
    implements _$$PaymentDestination_LightningAddressImplCopyWith<$Res> {
  __$$PaymentDestination_LightningAddressImplCopyWithImpl(
    _$PaymentDestination_LightningAddressImpl _value,
    $Res Function(_$PaymentDestination_LightningAddressImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$PaymentDestination_LightningAddressImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                as String,
      ),
    );
  }
}

/// @nodoc

class _$PaymentDestination_LightningAddressImpl
    extends PaymentDestination_LightningAddress {
  const _$PaymentDestination_LightningAddressImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'PaymentDestination.lightningAddress(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentDestination_LightningAddressImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PaymentDestination_LightningAddressImplCopyWith<
    _$PaymentDestination_LightningAddressImpl
  >
  get copyWith => __$$PaymentDestination_LightningAddressImplCopyWithImpl<
    _$PaymentDestination_LightningAddressImpl
  >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) {
    return lightningAddress(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) {
    return lightningAddress?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) {
    if (lightningAddress != null) {
      return lightningAddress(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) {
    return lightningAddress(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) {
    return lightningAddress?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) {
    if (lightningAddress != null) {
      return lightningAddress(this);
    }
    return orElse();
  }
}

abstract class PaymentDestination_LightningAddress extends PaymentDestination {
  const factory PaymentDestination_LightningAddress(final String field0) =
      _$PaymentDestination_LightningAddressImpl;
  const PaymentDestination_LightningAddress._() : super._();

  String get field0;

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PaymentDestination_LightningAddressImplCopyWith<
    _$PaymentDestination_LightningAddressImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PaymentDestination_UnknownImplCopyWith<$Res> {
  factory _$$PaymentDestination_UnknownImplCopyWith(
    _$PaymentDestination_UnknownImpl value,
    $Res Function(_$PaymentDestination_UnknownImpl) then,
  ) = __$$PaymentDestination_UnknownImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PaymentDestination_UnknownImplCopyWithImpl<$Res>
    extends
        _$PaymentDestinationCopyWithImpl<$Res, _$PaymentDestination_UnknownImpl>
    implements _$$PaymentDestination_UnknownImplCopyWith<$Res> {
  __$$PaymentDestination_UnknownImplCopyWithImpl(
    _$PaymentDestination_UnknownImpl _value,
    $Res Function(_$PaymentDestination_UnknownImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PaymentDestination
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$PaymentDestination_UnknownImpl extends PaymentDestination_Unknown {
  const _$PaymentDestination_UnknownImpl() : super._();

  @override
  String toString() {
    return 'PaymentDestination.unknown()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentDestination_UnknownImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() empty,
    required TResult Function(Bolt11Summary field0) bolt11,
    required TResult Function() malformedBolt11,
    required TResult Function(String field0) lightningAddress,
    required TResult Function() unknown,
  }) {
    return unknown();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? empty,
    TResult? Function(Bolt11Summary field0)? bolt11,
    TResult? Function()? malformedBolt11,
    TResult? Function(String field0)? lightningAddress,
    TResult? Function()? unknown,
  }) {
    return unknown?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? empty,
    TResult Function(Bolt11Summary field0)? bolt11,
    TResult Function()? malformedBolt11,
    TResult Function(String field0)? lightningAddress,
    TResult Function()? unknown,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PaymentDestination_Empty value) empty,
    required TResult Function(PaymentDestination_Bolt11 value) bolt11,
    required TResult Function(PaymentDestination_MalformedBolt11 value)
    malformedBolt11,
    required TResult Function(PaymentDestination_LightningAddress value)
    lightningAddress,
    required TResult Function(PaymentDestination_Unknown value) unknown,
  }) {
    return unknown(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PaymentDestination_Empty value)? empty,
    TResult? Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult? Function(PaymentDestination_MalformedBolt11 value)?
    malformedBolt11,
    TResult? Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult? Function(PaymentDestination_Unknown value)? unknown,
  }) {
    return unknown?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PaymentDestination_Empty value)? empty,
    TResult Function(PaymentDestination_Bolt11 value)? bolt11,
    TResult Function(PaymentDestination_MalformedBolt11 value)? malformedBolt11,
    TResult Function(PaymentDestination_LightningAddress value)?
    lightningAddress,
    TResult Function(PaymentDestination_Unknown value)? unknown,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown(this);
    }
    return orElse();
  }
}

abstract class PaymentDestination_Unknown extends PaymentDestination {
  const factory PaymentDestination_Unknown() = _$PaymentDestination_UnknownImpl;
  const PaymentDestination_Unknown._() : super._();
}

/// @nodoc
mixin _$TradeStep {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BuyerStep field0) buyer,
    required TResult Function(SellerStep field0) seller,
    required TResult Function() disputed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BuyerStep field0)? buyer,
    TResult? Function(SellerStep field0)? seller,
    TResult? Function()? disputed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BuyerStep field0)? buyer,
    TResult Function(SellerStep field0)? seller,
    TResult Function()? disputed,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TradeStep_Buyer value) buyer,
    required TResult Function(TradeStep_Seller value) seller,
    required TResult Function(TradeStep_Disputed value) disputed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TradeStep_Buyer value)? buyer,
    TResult? Function(TradeStep_Seller value)? seller,
    TResult? Function(TradeStep_Disputed value)? disputed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TradeStep_Buyer value)? buyer,
    TResult Function(TradeStep_Seller value)? seller,
    TResult Function(TradeStep_Disputed value)? disputed,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TradeStepCopyWith<$Res> {
  factory $TradeStepCopyWith(TradeStep value, $Res Function(TradeStep) then) =
      _$TradeStepCopyWithImpl<$Res, TradeStep>;
}

/// @nodoc
class _$TradeStepCopyWithImpl<$Res, $Val extends TradeStep>
    implements $TradeStepCopyWith<$Res> {
  _$TradeStepCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$TradeStep_BuyerImplCopyWith<$Res> {
  factory _$$TradeStep_BuyerImplCopyWith(
    _$TradeStep_BuyerImpl value,
    $Res Function(_$TradeStep_BuyerImpl) then,
  ) = __$$TradeStep_BuyerImplCopyWithImpl<$Res>;
  @useResult
  $Res call({BuyerStep field0});
}

/// @nodoc
class __$$TradeStep_BuyerImplCopyWithImpl<$Res>
    extends _$TradeStepCopyWithImpl<$Res, _$TradeStep_BuyerImpl>
    implements _$$TradeStep_BuyerImplCopyWith<$Res> {
  __$$TradeStep_BuyerImplCopyWithImpl(
    _$TradeStep_BuyerImpl _value,
    $Res Function(_$TradeStep_BuyerImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$TradeStep_BuyerImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                as BuyerStep,
      ),
    );
  }
}

/// @nodoc

class _$TradeStep_BuyerImpl extends TradeStep_Buyer {
  const _$TradeStep_BuyerImpl(this.field0) : super._();

  @override
  final BuyerStep field0;

  @override
  String toString() {
    return 'TradeStep.buyer(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TradeStep_BuyerImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TradeStep_BuyerImplCopyWith<_$TradeStep_BuyerImpl> get copyWith =>
      __$$TradeStep_BuyerImplCopyWithImpl<_$TradeStep_BuyerImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BuyerStep field0) buyer,
    required TResult Function(SellerStep field0) seller,
    required TResult Function() disputed,
  }) {
    return buyer(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BuyerStep field0)? buyer,
    TResult? Function(SellerStep field0)? seller,
    TResult? Function()? disputed,
  }) {
    return buyer?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BuyerStep field0)? buyer,
    TResult Function(SellerStep field0)? seller,
    TResult Function()? disputed,
    required TResult orElse(),
  }) {
    if (buyer != null) {
      return buyer(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TradeStep_Buyer value) buyer,
    required TResult Function(TradeStep_Seller value) seller,
    required TResult Function(TradeStep_Disputed value) disputed,
  }) {
    return buyer(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TradeStep_Buyer value)? buyer,
    TResult? Function(TradeStep_Seller value)? seller,
    TResult? Function(TradeStep_Disputed value)? disputed,
  }) {
    return buyer?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TradeStep_Buyer value)? buyer,
    TResult Function(TradeStep_Seller value)? seller,
    TResult Function(TradeStep_Disputed value)? disputed,
    required TResult orElse(),
  }) {
    if (buyer != null) {
      return buyer(this);
    }
    return orElse();
  }
}

abstract class TradeStep_Buyer extends TradeStep {
  const factory TradeStep_Buyer(final BuyerStep field0) = _$TradeStep_BuyerImpl;
  const TradeStep_Buyer._() : super._();

  BuyerStep get field0;

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TradeStep_BuyerImplCopyWith<_$TradeStep_BuyerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TradeStep_SellerImplCopyWith<$Res> {
  factory _$$TradeStep_SellerImplCopyWith(
    _$TradeStep_SellerImpl value,
    $Res Function(_$TradeStep_SellerImpl) then,
  ) = __$$TradeStep_SellerImplCopyWithImpl<$Res>;
  @useResult
  $Res call({SellerStep field0});
}

/// @nodoc
class __$$TradeStep_SellerImplCopyWithImpl<$Res>
    extends _$TradeStepCopyWithImpl<$Res, _$TradeStep_SellerImpl>
    implements _$$TradeStep_SellerImplCopyWith<$Res> {
  __$$TradeStep_SellerImplCopyWithImpl(
    _$TradeStep_SellerImpl _value,
    $Res Function(_$TradeStep_SellerImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$TradeStep_SellerImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                as SellerStep,
      ),
    );
  }
}

/// @nodoc

class _$TradeStep_SellerImpl extends TradeStep_Seller {
  const _$TradeStep_SellerImpl(this.field0) : super._();

  @override
  final SellerStep field0;

  @override
  String toString() {
    return 'TradeStep.seller(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TradeStep_SellerImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TradeStep_SellerImplCopyWith<_$TradeStep_SellerImpl> get copyWith =>
      __$$TradeStep_SellerImplCopyWithImpl<_$TradeStep_SellerImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BuyerStep field0) buyer,
    required TResult Function(SellerStep field0) seller,
    required TResult Function() disputed,
  }) {
    return seller(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BuyerStep field0)? buyer,
    TResult? Function(SellerStep field0)? seller,
    TResult? Function()? disputed,
  }) {
    return seller?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BuyerStep field0)? buyer,
    TResult Function(SellerStep field0)? seller,
    TResult Function()? disputed,
    required TResult orElse(),
  }) {
    if (seller != null) {
      return seller(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TradeStep_Buyer value) buyer,
    required TResult Function(TradeStep_Seller value) seller,
    required TResult Function(TradeStep_Disputed value) disputed,
  }) {
    return seller(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TradeStep_Buyer value)? buyer,
    TResult? Function(TradeStep_Seller value)? seller,
    TResult? Function(TradeStep_Disputed value)? disputed,
  }) {
    return seller?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TradeStep_Buyer value)? buyer,
    TResult Function(TradeStep_Seller value)? seller,
    TResult Function(TradeStep_Disputed value)? disputed,
    required TResult orElse(),
  }) {
    if (seller != null) {
      return seller(this);
    }
    return orElse();
  }
}

abstract class TradeStep_Seller extends TradeStep {
  const factory TradeStep_Seller(final SellerStep field0) =
      _$TradeStep_SellerImpl;
  const TradeStep_Seller._() : super._();

  SellerStep get field0;

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TradeStep_SellerImplCopyWith<_$TradeStep_SellerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TradeStep_DisputedImplCopyWith<$Res> {
  factory _$$TradeStep_DisputedImplCopyWith(
    _$TradeStep_DisputedImpl value,
    $Res Function(_$TradeStep_DisputedImpl) then,
  ) = __$$TradeStep_DisputedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$TradeStep_DisputedImplCopyWithImpl<$Res>
    extends _$TradeStepCopyWithImpl<$Res, _$TradeStep_DisputedImpl>
    implements _$$TradeStep_DisputedImplCopyWith<$Res> {
  __$$TradeStep_DisputedImplCopyWithImpl(
    _$TradeStep_DisputedImpl _value,
    $Res Function(_$TradeStep_DisputedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TradeStep
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$TradeStep_DisputedImpl extends TradeStep_Disputed {
  const _$TradeStep_DisputedImpl() : super._();

  @override
  String toString() {
    return 'TradeStep.disputed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$TradeStep_DisputedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BuyerStep field0) buyer,
    required TResult Function(SellerStep field0) seller,
    required TResult Function() disputed,
  }) {
    return disputed();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BuyerStep field0)? buyer,
    TResult? Function(SellerStep field0)? seller,
    TResult? Function()? disputed,
  }) {
    return disputed?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BuyerStep field0)? buyer,
    TResult Function(SellerStep field0)? seller,
    TResult Function()? disputed,
    required TResult orElse(),
  }) {
    if (disputed != null) {
      return disputed();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TradeStep_Buyer value) buyer,
    required TResult Function(TradeStep_Seller value) seller,
    required TResult Function(TradeStep_Disputed value) disputed,
  }) {
    return disputed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TradeStep_Buyer value)? buyer,
    TResult? Function(TradeStep_Seller value)? seller,
    TResult? Function(TradeStep_Disputed value)? disputed,
  }) {
    return disputed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TradeStep_Buyer value)? buyer,
    TResult Function(TradeStep_Seller value)? seller,
    TResult Function(TradeStep_Disputed value)? disputed,
    required TResult orElse(),
  }) {
    if (disputed != null) {
      return disputed(this);
    }
    return orElse();
  }
}

abstract class TradeStep_Disputed extends TradeStep {
  const factory TradeStep_Disputed() = _$TradeStep_DisputedImpl;
  const TradeStep_Disputed._() : super._();
}
