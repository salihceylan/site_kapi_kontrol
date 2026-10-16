// OTOMATİK ÜRETİLDİ: server/src/security/password_policy.js içindeki COMMON_PASSWORDS ve COMMON_BASES
// listelerinin kopyası (katlanmış, ASCII). Elle düzenlemeyin; sunucu listesi değişince yeniden üretin
// (test/password_policy_test.dart sunucu dosyası varsa iki listeyi karşılaştırır ve eşitsizlikte kırılır).

/// Doğrudan reddedilen yaygın parolalar (katlanmış biçim).
const Set<String> kCommonPasswords = <String>{
  r'12345678', r'123456789', r'1234567890', r'12345678910', r'0123456789', r'11111111',
  r'00000000', r'22222222', r'12341234', r'11223344', r'12121212', r'123123123', r'123321123',
  r'987654321', r'87654321', r'9876543210', r'123654789', r'147258369', r'159753456', r'741852963',
  r'963852741', r'147852369', r'123456654321', r'112233445566', r'1234512345', r'1122334455',
  r'5555555555', r'1231231234', r'20202020', r'19191919', r'1q2w3e4r', r'1q2w3e4r5t',
  r'1q2w3e4r5t6y', r'1qaz2wsx', r'1qaz2wsx3edc', r'q1w2e3r4', r'q1w2e3r4t5', r'qwerty12',
  r'qwerty123', r'qwerty1234', r'qwertyuiop', r'qwertyui', r'qwe12345', r'qweasdzxc', r'qazwsxedc',
  r'zaq12wsx', r'asdfghjk', r'asdfghjkl', r'asdf1234', r'zxcvbnm1', r'zxcvbnm123', r'1234qwer',
  r'abcd1234', r'abc12345', r'abcd12345', r'abcdefgh', r'a1234567', r'a12345678', r'1234567a',
  r'123456789a', r'123456789q', r'aa123456', r'aa12345678', r'a1b2c3d4', r'1a2b3c4d', r'aaaaaaaa',
  r'qqqqqqqq', r'password', r'password1', r'password12', r'password123', r'password1234',
  r'passw0rd', r'p@ssw0rd', r'p@ssword', r'p@55w0rd', r'iloveyou', r'iloveyou1', r'admin123',
  r'admin1234', r'administrator', r'welcome1', r'welcome123', r'letmein1', r'letmein123',
  r'changeme', r'changeme1', r'trustno1', r'sunshine', r'princess', r'football', r'baseball',
  r'superman', r'starwars', r'whatever', r'computer', r'internet', r'michelle', r'jennifer',
  r'liverpool', r'chelsea1', r'arsenal1', r'barcelona', r'realmadrid', r'pokemon1', r'minecraft',
  r'samsung1', r'iphone12', r'google123', r'facebook', r'instagram', r'whatsapp', r'helloworld',
  r'hello123', r'lovelove', r'freedom1', r'shadow12', r'michael1', r'charlie1', r'jordan23',
  r'monkey12', r'dragon12', r'master12', r'default1', r'guest123', r'user1234', r'root1234',
  r'test1234', r'test12345', r'qwerty11', r'sifre123', r'sifre1234', r'sifre12345', r'sifresifre',
  r'sifrem123', r'sifremyok', r'parola123', r'parola1234', r'parola12345', r'parolam123',
  r'yenisifre1', r'gizlisifre', r'deneme123', r'deneme1234', r'denemeler', r'kullanici',
  r'kullanici1', r'yonetici', r'yonetici1', r'yonetici123', r'merhaba123', r'selamlar',
  r'seniseviyorum', r'seviyorum', r'askim123', r'askimsin', r'canimsin', r'hayatim1', r'birtanem',
  r'kalbimsin', r'bismillah', r'elhamdulillah', r'allahuekber', r'ataturk1881', r'ataturk1938',
  r'mustafakemal', r'turkiye123', r'turkiye1923', r'cumhuriyet', r'cumhuriyet1923', r'galatasaray',
  r'galatasaray1905', r'cimbom1905', r'aslan1905', r'fenerbahce', r'fenerbahce1907',
  r'kanarya1907', r'besiktas1903', r'kartal1903', r'carsi1903', r'trabzonspor', r'trabzonspor61',
  r'trabzonspor1967', r'bursaspor', r'goztepe1925', r'istanbul', r'istanbul34', r'istanbul1453',
  r'ankara06', r'ankara123', r'izmir035', r'izmir3535', r'antalya07', r'bursa016', r'trabzon61',
  r'diyarbakir', r'diyarbakir21', r'konya042', r'adana001', r'apartman1', r'apartman123',
  r'site1234', r'site12345', r'daire123', r'daire1234', r'kapi1234', r'kapi12345', r'kapikontrol',
  r'smartkeypass', r'ahbu1234', r'gudeteknoloji', r'yonetim123', r'aidat123',
};

/// Yaygın sözcükler: tek başına ya da yalnız rakam/im ekiyle reddedilir.
const Set<String> kCommonPasswordBases = <String>{
  r'password', r'passw0rd', r'p@ssw0rd', r'qwerty', r'qwertyui', r'qwertyuiop', r'admin',
  r'administrator', r'welcome', r'letmein', r'iloveyou', r'monkey', r'dragon', r'master', r'login',
  r'sunshine', r'football', r'abc', r'abcd', r'abcdefgh', r'asdf', r'asdfgh', r'zxcvbnm', r'test',
  r'deneme', r'sifre', r'sifrem', r'parola', r'parolam', r'gizli', r'merhaba', r'selam', r'askim',
  r'canim', r'hayatim', r'seniseviyorum', r'galatasaray', r'cimbom', r'fenerbahce', r'besiktas',
  r'trabzon', r'trabzonspor', r'istanbul', r'ankara', r'izmir', r'turkiye', r'ataturk', r'kapi',
  r'site', r'daire', r'apartman', r'yonetici', r'kullanici', r'ahbu', r'smartkeypass',
  r'gudeteknoloji',
};
