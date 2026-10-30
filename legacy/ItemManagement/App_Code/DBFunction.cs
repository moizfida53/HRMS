using System;
using System.Collections.Generic;
using System.Web;
using System.Data;
using System.Configuration;
using System.Data.SqlClient;

/// <summary>
/// Summary description for DB_Functionscs
/// </summary>
public class DBFunction
{
    public static DataSet GetData(string query, Dictionary<string, object> Param, bool StoredProcedure = false)
    {
        try
        {
            DataSet ds = new DataSet();
            using (SqlConnection con = new SqlConnection(ConfigurationManager.ConnectionStrings["SqlConnectionString"].ConnectionString))
            {

                using (SqlCommand cmd = new SqlCommand(query, con))
                {
                    if (StoredProcedure)
                        cmd.CommandType = CommandType.StoredProcedure;

                    if (Param.Keys.Count > 0)
                    {
                        foreach (var pair in Param)
                        {
                            cmd.Parameters.AddWithValue(pair.Key, pair.Value);
                        }
                    }

                    using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                    {
                        con.Open();
                        da.Fill(ds);
                        con.Close();
                    }
                }
            }
            return ds;
        }
        catch
        {
            return null;
        }

    }
    public static void ExecuteQuery(string Query, Dictionary<string, object> Param, bool StoredProcedure = false)
    {
        try
        {
            using (SqlConnection con = new SqlConnection(ConfigurationManager.ConnectionStrings["SqlConnectionString"].ConnectionString))
            {
                using (SqlCommand cmd = new SqlCommand(Query, con))
                {
                    if (StoredProcedure)
                        cmd.CommandType = CommandType.StoredProcedure;

                    if (Param.Keys.Count > 0)
                    {
                        foreach (var pair in Param)
                        {
                            cmd.Parameters.AddWithValue(pair.Key, pair.Value);
                        }
                    }
                    con.Open();
                    cmd.ExecuteNonQuery();
                    con.Close();
                }
            }
        }
        catch (Exception ex)
        {
            throw new Exception(ex.Message);
        }

    }
    public static string GetValue(string sqlStr, string defaultvalue = "")
    {
        string value = defaultvalue;
        SqlConnection conn = new SqlConnection(ConfigurationManager.ConnectionStrings["SqlConnectionString"].ConnectionString);
        conn.Open();
        SqlCommand cmd = new SqlCommand(sqlStr, conn);
        SqlDataReader dr = cmd.ExecuteReader();
        while (dr.Read())
        {
            if (dr[0] != DBNull.Value)
                value = dr[0].ToString();
        }
        conn.Close();
        return value;
    }
}