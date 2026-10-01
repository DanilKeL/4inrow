import { resolveMx } from 'node:dns/promises';
import { domainToASCII } from 'node:url';

export interface MailMessage {
  email: string;
  username: string;
  token: string;
}

export interface Mailer {
  validateRecipient?(email: string): Promise<boolean>;
  sendVerification(message: MailMessage): Promise<void>;
  sendPasswordReset(message: MailMessage): Promise<void>;
}

type MxResolver = (domain: string) => Promise<readonly { exchange: string; priority: number }[]>;

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function renderEmail(options: {
  publicUrl: string;
  preheader: string;
  title: string;
  username: string;
  body: string;
  actionLabel: string;
  actionUrl: string;
  expiry: string;
  ignoreText: string;
}) {
  const actionUrl = escapeHtml(options.actionUrl);
  const logoUrl = escapeHtml(`${options.publicUrl}/icons/email-logo.png?v=20261001`);
  return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(options.title)}</title>
  </head>
  <body style="margin:0;background:#f4f6fb;color:#172033;font-family:Arial,Helvetica,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${escapeHtml(options.preheader)}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f4f6fb;">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background:#ffffff;border:1px solid #e5e9f2;border-radius:20px;">
            <tr>
              <td style="padding:32px 40px 12px;">
                <img src="${logoUrl}" width="48" height="48" alt="FOUR³" style="display:block;border:0;border-radius:12px;">
              </td>
            </tr>
            <tr>
              <td style="padding:12px 40px 36px;">
                <p style="margin:0 0 10px;color:#2f5bea;font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;">FOUR³ · 4inrow.ru</p>
                <h1 style="margin:0 0 20px;color:#172033;font-size:28px;line-height:1.25;">${escapeHtml(options.title)}</h1>
                <p style="margin:0 0 12px;font-size:16px;line-height:1.6;">Здравствуйте, ${escapeHtml(options.username)}!</p>
                <p style="margin:0 0 24px;font-size:16px;line-height:1.6;">${escapeHtml(options.body)}</p>
                <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                  <tr>
                    <td bgcolor="#2f5bea" style="border-radius:10px;">
                      <a href="${actionUrl}" style="display:inline-block;padding:14px 22px;color:#ffffff;font-size:16px;font-weight:700;text-decoration:none;border-radius:10px;">${escapeHtml(options.actionLabel)}</a>
                    </td>
                  </tr>
                </table>
                <p style="margin:24px 0 8px;color:#596579;font-size:14px;line-height:1.5;">${escapeHtml(options.expiry)}</p>
                <p style="margin:0 0 24px;color:#596579;font-size:14px;line-height:1.5;">${escapeHtml(options.ignoreText)}</p>
                <p style="margin:0;color:#7d8798;font-size:12px;line-height:1.5;word-break:break-all;">Если кнопка не открывается, скопируйте ссылку:<br><a href="${actionUrl}" style="color:#2f5bea;">${actionUrl}</a></p>
              </td>
            </tr>
          </table>
          <p style="margin:18px 0 0;color:#8791a2;font-size:12px;">Сервис FOUR³ · <a href="${escapeHtml(options.publicUrl)}" style="color:#64708a;">4inrow.ru</a></p>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

export class ResendMailer implements Mailer {
  private readonly domainCache = new Map<string, { valid: boolean; expires: number }>();

  constructor(
    private apiKey: string,
    private from: string,
    private publicUrl: string,
    private resolveMxRecords: MxResolver = resolveMx,
  ) {}

  static fromEnv() {
    const apiKey = process.env.RESEND_API_KEY?.trim();
    if (!apiKey) return null;
    return new ResendMailer(
      apiKey,
      process.env.FOUR_MAIL_FROM?.trim() || 'FOUR³ <no-reply@4inrow.ru>',
      (process.env.FOUR_PUBLIC_URL?.trim() || 'https://4inrow.ru').replace(/\/$/, ''),
    );
  }

  sendVerification({ email, username, token }: MailMessage) {
    const link = `${this.publicUrl}/auth/verify?token=${encodeURIComponent(token)}`;
    return this.send(
      email,
      'Подтверждение регистрации в FOUR³',
      `Здравствуйте, ${username}!\n\nПодтвердите адрес электронной почты, чтобы завершить регистрацию в FOUR³:\n${link}\n\nСсылка действует 24 часа.\nЕсли вы не регистрировались в FOUR³, просто проигнорируйте это письмо.\n\nFOUR³ · ${this.publicUrl}`,
      renderEmail({
        publicUrl: this.publicUrl,
        preheader: 'Подтвердите адрес электронной почты, чтобы завершить регистрацию.',
        title: 'Подтвердите регистрацию',
        username,
        body: 'Подтвердите адрес электронной почты, чтобы завершить регистрацию в FOUR³.',
        actionLabel: 'Подтвердить email',
        actionUrl: link,
        expiry: 'Ссылка действует 24 часа.',
        ignoreText: 'Если вы не регистрировались в FOUR³, просто проигнорируйте это письмо.',
      }),
    );
  }

  sendPasswordReset({ email, username, token }: MailMessage) {
    const link = `${this.publicUrl}/?reset=${encodeURIComponent(token)}`;
    return this.send(
      email,
      'Сброс пароля FOUR³',
      `Здравствуйте, ${username}!\n\nМы получили запрос на смену пароля для вашей учётной записи FOUR³. Задайте новый пароль по ссылке:\n${link}\n\nСсылка действует 1 час.\nЕсли вы не запрашивали сброс пароля, ничего делать не нужно.\n\nFOUR³ · ${this.publicUrl}`,
      renderEmail({
        publicUrl: this.publicUrl,
        preheader: 'Откройте безопасную ссылку, чтобы задать новый пароль.',
        title: 'Сброс пароля',
        username,
        body: 'Мы получили запрос на смену пароля для вашей учётной записи FOUR³.',
        actionLabel: 'Задать новый пароль',
        actionUrl: link,
        expiry: 'Ссылка действует 1 час.',
        ignoreText: 'Если вы не запрашивали сброс пароля, ничего делать не нужно.',
      }),
    );
  }

  async validateRecipient(email: string) {
    const separator = email.lastIndexOf('@');
    if (separator < 1) return true;
    const domain = domainToASCII(
      email
        .slice(separator + 1)
        .trim()
        .toLocaleLowerCase('und'),
    );
    if (!domain || !/^[a-z0-9.-]+$/.test(domain)) return true;
    const cached = this.domainCache.get(domain);
    if (cached && cached.expires > Date.now()) return cached.valid;
    try {
      const records = await this.resolveMxRecords(domain);
      const valid = records.some((record) => Boolean(record.exchange && record.exchange !== '.'));
      this.domainCache.set(domain, { valid, expires: Date.now() + 10 * 60_000 });
      return valid;
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      const permanent = code === 'ENODATA' || code === 'ENOTFOUND' || code === 'EFORMERR';
      this.domainCache.set(domain, {
        valid: false,
        expires: Date.now() + (permanent ? 10 * 60_000 : 30_000),
      });
      // Fail closed: sending blindly during a DNS outage creates bounces and harms reputation.
      return false;
    }
  }

  private async send(to: string, subject: string, text: string, html: string) {
    if (!(await this.validateRecipient(to))) throw new Error('Recipient domain has no mail server');
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: this.from,
        to: [to],
        subject,
        text,
        html,
        headers: {
          'Auto-Submitted': 'auto-generated',
          'BIMI-Selector': 'v=BIMI1; s=default;',
          'X-Auto-Response-Suppress': 'All',
        },
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      const requestId = response.headers.get('x-request-id');
      throw new Error(
        `Resend rejected email (${response.status}${requestId ? `, ${requestId}` : ''})`,
      );
    }
  }
}
