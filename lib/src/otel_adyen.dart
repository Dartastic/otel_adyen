// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_adyen_suppression.dart';

const _tracerName = 'dartastic_otel_libs_adyen';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class AdyenResult {
  const AdyenResult({
    this.pspReference,
    this.merchantAccount,
    this.paymentMethodType,
    this.resultCode,
    this.refusalReason,
    this.amountMinor,
    this.currency,
    this.threeDsAuthenticated,
    this.shopperCountry,
    this.statusCode,
  });

  /// Adyen's transaction id — primary correlation key.
  final String? pspReference;

  /// Merchant account name (sub-merchants split by this).
  final String? merchantAccount;

  /// `visa`, `mc`, `ideal`, `applepay`, `paypal`, `directEbanking`,
  /// `klarna_account`, etc.
  final String? paymentMethodType;

  /// `Authorised`, `Refused`, `Cancelled`, `Pending`, `Received`,
  /// `ChallengeShopper`, `IdentifyShopper`, `Error`.
  final String? resultCode;

  /// Adyen refusal reason — top diagnostic dim for declined payments.
  final String? refusalReason;
  final int? amountMinor;
  final String? currency;

  /// True if the txn went through 3DS challenge — separate signal
  /// from whether it succeeded (3DS-passing decline still happens).
  final bool? threeDsAuthenticated;
  final String? shopperCountry;
  final int? statusCode;
}

class AdyenCallResult<T> {
  const AdyenCallResult({required this.value, this.result});
  final T value;
  final AdyenResult? result;
}

/// Wraps an Adyen API call in a CLIENT span. [operation] is the API
/// op like `payments`, `payments.details`, `paymentMethods`,
/// `payments.captures`, `splits.create`, `terminal.api.sync`.
Future<T> tracedAdyen<T>({
  required String operation,
  required Future<AdyenCallResult<T>> Function() invoke,
  String environment = 'live',
}) async {
  if (adyenInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'adyen',
    'rpc.method': operation,
    'adyen.environment': environment,
  };

  final span = _tracer().startSpan(
    'adyen $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.pspReference != null) {
        extras.add(OTel.attributeString(
          'adyen.psp_reference',
          r.result!.pspReference!,
        ));
      }
      if (r.result!.merchantAccount != null) {
        extras.add(OTel.attributeString(
          'adyen.merchant_account',
          r.result!.merchantAccount!,
        ));
      }
      if (r.result!.paymentMethodType != null) {
        extras.add(OTel.attributeString(
          'adyen.payment_method.type',
          r.result!.paymentMethodType!,
        ));
      }
      if (r.result!.resultCode != null) {
        extras.add(OTel.attributeString(
          'adyen.result_code',
          r.result!.resultCode!,
        ));
        if (r.result!.resultCode == 'Refused' ||
            r.result!.resultCode == 'Error' ||
            r.result!.resultCode == 'Cancelled') {
          span.setStatus(
            SpanStatusCode.Error,
            'Adyen result_code=${r.result!.resultCode}',
          );
        }
      }
      if (r.result!.refusalReason != null) {
        extras.add(OTel.attributeString(
          'adyen.refusal_reason',
          r.result!.refusalReason!,
        ));
      }
      if (r.result!.amountMinor != null) {
        extras.add(OTel.attributeInt(
          'adyen.amount.minor',
          r.result!.amountMinor!,
        ));
      }
      if (r.result!.currency != null) {
        extras.add(OTel.attributeString(
          'adyen.currency',
          r.result!.currency!,
        ));
      }
      if (r.result!.threeDsAuthenticated != null) {
        extras.add(OTel.attributeBool(
          'adyen.three_ds.authenticated',
          r.result!.threeDsAuthenticated!,
        ));
      }
      if (r.result!.shopperCountry != null) {
        extras.add(OTel.attributeString(
          'adyen.shopper_country',
          r.result!.shopperCountry!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Adyen HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
