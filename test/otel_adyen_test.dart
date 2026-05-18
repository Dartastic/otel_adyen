// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_adyen/otel_adyen.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_adyen-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('Authorised card payment records full context', () async {
    await tracedAdyen<String>(
      operation: 'payments',
      invoke: () async => const AdyenCallResult(
        value: 'ok',
        result: AdyenResult(
          pspReference: 'PSP-1',
          merchantAccount: 'AcmeECOM',
          paymentMethodType: 'visa',
          resultCode: 'Authorised',
          amountMinor: 12500,
          currency: 'EUR',
          threeDsAuthenticated: true,
          shopperCountry: 'DE',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('adyen payments')!);
    expect(a['adyen.merchant_account'], 'AcmeECOM');
    expect(a['adyen.payment_method.type'], 'visa');
    expect(a['adyen.result_code'], 'Authorised');
    expect(a['adyen.three_ds.authenticated'], true);
    expect(a['adyen.shopper_country'], 'DE');
  });

  test('Refused records refusal_reason and span error', () async {
    await tracedAdyen<String>(
      operation: 'payments',
      invoke: () async => const AdyenCallResult(
        value: 'ok',
        result: AdyenResult(
          resultCode: 'Refused',
          refusalReason: 'Not enough balance',
        ),
      ),
    );
    final span = spans.findSpanByName('adyen payments')!;
    expect(span.status, SpanStatusCode.Error);
    expect(attrsOf(span)['adyen.refusal_reason'], 'Not enough balance');
  });

  test('suppression skips spans', () async {
    await runWithoutAdyenInstrumentationAsync(() async {
      await tracedAdyen<String>(
        operation: 'paymentMethods',
        invoke: () async => const AdyenCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('adyen '), isEmpty);
  });
}
