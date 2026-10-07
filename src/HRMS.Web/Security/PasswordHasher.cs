using System.Buffers.Binary;
using System.Security.Cryptography;

namespace HRMS.Web.Security;

public interface IPasswordHasher
{
    string Hash(string password);

    /// <summary>
    /// Verifies a password against a stored hash in constant time.
    /// <paramref name="needsRehash"/> is true when the stored hash used fewer
    /// iterations than the current policy, so it can be silently upgraded on
    /// the next successful sign-in.
    /// </summary>
    bool Verify(string password, string? storedHash, out bool needsRehash);

    /// <summary>
    /// Burns roughly the same time as a real verification. Called when the
    /// username does not exist so that response timing does not reveal which
    /// usernames are valid.
    /// </summary>
    void BurnTime();
}

/// <summary>
/// PBKDF2-HMAC-SHA256 password hashing.
/// <para>
/// Format (base64 encoded):
/// <code>
///   byte  0      format marker, 0x01
///   bytes 1-4    iteration count, big-endian
///   bytes 5-20   salt, 16 bytes
///   bytes 21-52  derived subkey, 32 bytes
/// </code>
/// The iteration count travels with the hash, so raising the work factor later
/// does not invalidate existing passwords - they are re-hashed transparently
/// the next time their owner signs in.
/// </para>
/// </summary>
public sealed class PasswordHasher : IPasswordHasher
{
    private const byte FormatMarker = 0x01;
    private const int SaltSize = 16;
    private const int SubkeySize = 32;
    private const int HeaderSize = 1 + 4;

    /// <summary>OWASP guidance for PBKDF2-HMAC-SHA256 at time of writing.</summary>
    private const int CurrentIterations = 210_000;

    private static readonly HashAlgorithmName Algorithm = HashAlgorithmName.SHA256;

    public string Hash(string password)
    {
        ArgumentException.ThrowIfNullOrEmpty(password);

        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var subkey = Rfc2898DeriveBytes.Pbkdf2(password, salt, CurrentIterations, Algorithm, SubkeySize);

        var output = new byte[HeaderSize + SaltSize + SubkeySize];
        output[0] = FormatMarker;
        BinaryPrimitives.WriteInt32BigEndian(output.AsSpan(1, 4), CurrentIterations);
        salt.CopyTo(output.AsSpan(HeaderSize));
        subkey.CopyTo(output.AsSpan(HeaderSize + SaltSize));

        return Convert.ToBase64String(output);
    }

    public bool Verify(string password, string? storedHash, out bool needsRehash)
    {
        needsRehash = false;

        if (string.IsNullOrEmpty(password) || string.IsNullOrWhiteSpace(storedHash))
        {
            BurnTime();
            return false;
        }

        byte[] decoded;
        try
        {
            decoded = Convert.FromBase64String(storedHash);
        }
        catch (FormatException)
        {
            BurnTime();
            return false;
        }

        if (decoded.Length != HeaderSize + SaltSize + SubkeySize || decoded[0] != FormatMarker)
        {
            BurnTime();
            return false;
        }

        var iterations = BinaryPrimitives.ReadInt32BigEndian(decoded.AsSpan(1, 4));

        // A corrupt or hostile iteration count could otherwise be used to pin a
        // request thread for minutes at a time.
        if (iterations is < 1_000 or > 2_000_000)
        {
            BurnTime();
            return false;
        }

        var salt = decoded.AsSpan(HeaderSize, SaltSize).ToArray();
        var expected = decoded.AsSpan(HeaderSize + SaltSize, SubkeySize).ToArray();
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, Algorithm, SubkeySize);

        // Constant-time comparison: a byte-by-byte early exit leaks the hash
        // prefix through response timing.
        var matched = CryptographicOperations.FixedTimeEquals(actual, expected);

        if (matched && iterations < CurrentIterations)
        {
            needsRehash = true;
        }

        return matched;
    }

    public void BurnTime()
    {
        // Same algorithm, same work factor, discarded result.
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var burned = Rfc2898DeriveBytes.Pbkdf2("timing-equalisation", salt, CurrentIterations, Algorithm, SubkeySize);
        CryptographicOperations.ZeroMemory(burned);
    }
}
