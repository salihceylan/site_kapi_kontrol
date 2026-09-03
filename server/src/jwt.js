import jwt from 'jsonwebtoken';

function getJwtSecret() {
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET tanimli degil.');
  }
  return process.env.JWT_SECRET;
}

export function signAccessToken(user) {
  return jwt.sign(
    {
      sub: String(user.id),
      email: user.email,
      role: user.role,
    },
    getJwtSecret(),
    { expiresIn: process.env.JWT_EXPIRES_IN || '365d' },
  );
}

export function verifyAccessToken(token) {
  return jwt.verify(token, getJwtSecret());
}
