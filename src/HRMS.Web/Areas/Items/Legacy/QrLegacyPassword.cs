using System.Data;
using Microsoft.Data.SqlClient;

namespace HRMS.Web.Areas.Items.Legacy;

/// <summary>
/// QR Menu accounts moved from the old tblUser (db/qrmenu-merge, step 02) have no
/// HRMS password hash yet: they carry the old plain [Password] or the old POS
/// SHA2-512 hash (PosPasswordHash + PosPasswordSalt). SignInService accepts that
/// old password once and immediately replaces it with the HRMS hash.
/// </summary>
public static class QrLegacyPassword
{
    public static bool VerifyPosHash(long userId, string password)
    {
        if (string.IsNullOrEmpty(password) || password.Length > 50) return false;
        var cs = ConfigurationManager.ConnectionStrings["ConnStr"].ConnectionString;
        if (string.IsNullOrWhiteSpace(cs)) return false;

        try
        {
            using var con = new SqlConnection(cs);
            using var cmd = new SqlCommand(
                "SELECT CASE WHEN EXISTS (SELECT 1 FROM Security.Users " +
                "WHERE UserId = @UserId AND Deleted = 0 AND PosPasswordHash IS NOT NULL " +
                "AND PosPasswordHash = HASHBYTES('SHA2_512', PosPasswordSalt + CONVERT(VARBINARY(200), @Password))) " +
                "THEN 1 ELSE 0 END", con);
            cmd.Parameters.Add("@UserId", SqlDbType.BigInt).Value = userId;
            cmd.Parameters.Add("@Password", SqlDbType.NVarChar, 50).Value = password;   // same type the old sp_POS_Login hashed
            con.Open();
            return Convert.ToInt32(cmd.ExecuteScalar()) == 1;
        }
        catch (SqlException)
        {
            // merge step 02 not run on this database (no PosPasswordHash column) - nothing to check
            return false;
        }
    }
}
