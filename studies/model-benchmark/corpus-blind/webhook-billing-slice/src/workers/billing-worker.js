export async function applyPlanUpgrade(db, checkoutSession) {
  const { customer_email, metadata } = checkoutSession;
  const targetTier = metadata?.tier || 'pro';
  const seatDelta = Number(metadata?.seats || 5);

  const orgRes = await db.query(
    'SELECT id, seat_limit FROM organizations WHERE billing_email = $1',
    [customer_email]
  );
  if (orgRes.rowCount === 0) {
    throw new Error('Organization not found for billing email');
  }

  const org = orgRes.rows[0];
  const nextSeats = org.seat_limit + seatDelta;

  await db.query(
    'UPDATE organizations SET plan_tier = $1, seat_limit = $2, updated_at = NOW() WHERE id = $3',
    [targetTier, nextSeats, org.id]
  );
}
