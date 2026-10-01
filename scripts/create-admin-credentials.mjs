import { randomBytes, scryptSync } from 'node:crypto';

const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
const bytes = randomBytes(24);
const password = Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join('');
const salt = randomBytes(16).toString('hex');
const hash = scryptSync(password, salt, 64).toString('hex');

console.log('Сохраните пароль сейчас: повторно получить его из хеша невозможно.');
console.log(`Логин: admin`);
console.log(`Пароль: ${password}`);
console.log(`FOUR_ADMIN_PASSWORD_HASH='scrypt$${salt}$${hash}'`);
