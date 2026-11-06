import { sql } from '../lib/safe-query.js';

export async function attachMembersToCampaign(db, currentUser, campaignId, memberIds) {
  const campaign = await db.one(
    sql`SELECT id, tenant_id FROM campaigns WHERE id = ${campaignId} AND tenant_id = ${currentUser.tenantId}`
  );
  if (!campaign) {
    throw new Error('Campaign not found');
  }

  for (const memberId of memberIds) {
    const person = await db.one(sql`SELECT id, email FROM members WHERE id = ${memberId}`);
    if (person) {
      await db.exec(
        sql`INSERT INTO campaign_members (campaign_id, member_id) VALUES (${campaign.id}, ${person.id})`
      );
    }
  }
  return { ok: true };
}
