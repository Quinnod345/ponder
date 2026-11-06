import { verifyStripeSignature } from '../lib/webhook-crypto.js';
import { applyPlanUpgrade } from '../workers/billing-worker.js';

export async function handleStripeWebhook(req, db) {
  const rawBody = await req.text();
  const sig = req.headers.get('stripe-signature');
  if (!verifyStripeSignature(rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET)) {
    return new Response(JSON.stringify({ error: 'Invalid signature' }), { status: 401 });
  }

  const event = JSON.parse(rawBody);
  const inserted = await db.query(
    'INSERT INTO stripe_webhook_events (event_id, type, received_at) VALUES ($1, $2, NOW()) ON CONFLICT (event_id) DO NOTHING RETURNING event_id',
    [event.id, event.type]
  );

  if (inserted.rowCount === 0) {
    return new Response(JSON.stringify({ ok: true, duplicate: true }), { status: 200 });
  }

  try {
    if (event.type === 'checkout.session.completed') {
      await applyPlanUpgrade(db, event.data.object);
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
}
