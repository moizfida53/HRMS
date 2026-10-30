using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Data.SqlClient;
using System.Data;
using System.Collections.Concurrent;
using System.Reflection;

namespace Jar.Helper
{
    public class DB2
    {
        public static DataTable ToDataTable<T>(List<T> items)
        {
            DataTable dataTable = new DataTable(typeof(T).Name);

            //Get all the properties
            PropertyInfo[] Props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance);
            foreach (PropertyInfo prop in Props)
            {
                //Defining type of data column gives proper data table 
                var type = (prop.PropertyType.IsGenericType && prop.PropertyType.GetGenericTypeDefinition() == typeof(Nullable<>) ? Nullable.GetUnderlyingType(prop.PropertyType) : prop.PropertyType);
                //Setting column names as Property names
                dataTable.Columns.Add(prop.Name, type);
            }
            foreach (T item in items)
            {
                var values = new object[Props.Length];
                for (int i = 0; i < Props.Length; i++)
                {
                    //inserting property values to datatable rows
                    values[i] = Props[i].GetValue(item, null);
                }
                dataTable.Rows.Add(values);
            }
            //put a breakpoint here and check datatable
            return dataTable;
        }
        private static FixedSizedQueue<DBLogger> DBLog = new FixedSizedQueue<DBLogger>(1000);
        public DB2()
        {
        }
        public static string filename = AppDomain.CurrentDomain.BaseDirectory + "App_Data\\" + "log\\" + "Sp_logs.txt"; //----Log file path------//
        private static string _activeDBConn = SetDBConn();

        private static string SetDBConn()
        {
            string s = CommonLogic.ConnectionString("ConnStrPOS");
            return s;
        }

        public static string GetDBConn()
        {
            return _activeDBConn;
        }

        public static SqlConnection dbConn()
        {
            return new SqlConnection(DB2.GetDBConn());
        }


        public static int ExecuteStoredProc(string StoredProcName)
        {
            return ExecuteStoredProc(StoredProcName, null);
        }

        public static int ExecuteStoredProc(string StoredProcName, SqlParameter[] paramColl)
        {
            int ret = -1; string Exec = "";
            using (SqlConnection con = dbConn())
            {
                con.Open();
                using (SqlCommand dbCommand = new SqlCommand(StoredProcName, con))
                {
                    dbCommand.CommandType = CommandType.StoredProcedure;
                    dbCommand.CommandTimeout = 0;

                    if (paramColl != null)
                    {
                        foreach (SqlParameter sp in paramColl)
                        {
                            dbCommand.Parameters.Add(sp);
                        }
                    }
                    DateTime dt1 = DateTime.Now;
                    try
                    {
                        ret = dbCommand.ExecuteNonQuery();
                    }
                    catch (SqlException ex)
                    {
                        Exec = ex.Message;
                        throw;
                    }
                    finally
                    {
                        int tt = (int)DateTime.Now.Subtract(dt1).TotalMilliseconds;
                        DBLog.Enqueue(new DBLogger() { ExecTime = dt1, Procedure = StoredProcName, TimeTaken = tt, Exception = Exec });
                    } return ret;
                }
            }
        }

        public static int ExecuteSpRetVal(string StoredProcName, SqlParameter[] paramColl)
        {
            int ret = -1; string Exec = ""; int Cnt = 0;
            using (SqlConnection con = dbConn())
            {
                con.Open();
                using (SqlCommand dbCommand = new SqlCommand(StoredProcName, con))
                {
                    dbCommand.CommandType = CommandType.StoredProcedure;
                    dbCommand.CommandTimeout = 0;

                    if (paramColl != null)
                    {
                        foreach (SqlParameter sp in paramColl)
                        {
                            dbCommand.Parameters.Add(sp);
                        }
                    }
                    SqlParameter returnParameter = dbCommand.Parameters.Add("RetVal", SqlDbType.Int);
                    returnParameter.Direction = ParameterDirection.ReturnValue;
                    DateTime dt1 = DateTime.Now;
                    try
                    {
                        ret = dbCommand.ExecuteNonQuery();
                        Cnt = (int)returnParameter.Value;
                    }
                    catch (SqlException ex)
                    {
                        Exec = ex.Message;
                        throw;
                    }
                    finally
                    {
                        int tt = (int)DateTime.Now.Subtract(dt1).TotalMilliseconds;
                        DBLog.Enqueue(new DBLogger() { ExecTime = dt1, Procedure = StoredProcName, TimeTaken = tt, Exception = Exec });
                    } return Cnt;
                }
            }
        }
        public static object ExecuteStoredProcScaler(string StoredProcName, SqlParameter[] paramColl)
        {
            object ret = null; string Exec = "";
            using (SqlConnection con = dbConn())
            {
                con.Open();
                using (SqlCommand dbCommand = new SqlCommand(StoredProcName, con))
                {
                    dbCommand.CommandType = CommandType.StoredProcedure;
                    dbCommand.CommandTimeout = 0;

                    foreach (SqlParameter sp in paramColl)
                    {
                        dbCommand.Parameters.Add(sp);
                    }
                    DateTime dt1 = DateTime.Now;
                    try
                    {
                        ret = dbCommand.ExecuteScalar();
                    }
                    catch (SqlException ex)
                    {
                        Exec = ex.Message;
                        throw;
                    }
                    finally
                    {
                        int tt = (int)DateTime.Now.Subtract(dt1).TotalMilliseconds;
                        DBLog.Enqueue(new DBLogger() { ExecTime = dt1, Procedure = StoredProcName, TimeTaken = tt, Exception = Exec });
                    }
                    return ret;
                }
            }
        }

        public static DataSet ExecuteStoredProcDataSet(string StoredProcName)
        {
            return ExecuteStoredProcDataSet(StoredProcName, null);
        }

        public static DataSet ExecuteStoredProcDataSet(string StoredProcName, SqlParameter[] paramColl)
        {
            string Exec = "";
            using (SqlConnection con = dbConn())
            {
                con.Open();
                using (SqlCommand dbCommand = new SqlCommand(StoredProcName, con))
                {
                    dbCommand.CommandType = CommandType.StoredProcedure;
                    dbCommand.CommandTimeout = 0;

                    if (paramColl != null)
                    {
                        foreach (SqlParameter sp in paramColl)
                        {
                            dbCommand.Parameters.Add(sp);
                        }
                    }
                    SqlDataAdapter da = new SqlDataAdapter(dbCommand);
                    DataSet ds = new DataSet();
                    DateTime dt1 = DateTime.Now;
                    try
                    {
                        da.Fill(ds);
                    }
                    catch (SqlException ex)
                    {
                        Exec = ex.Message;
                        throw;
                    }
                    finally
                    {
                        int tt = (int)DateTime.Now.Subtract(dt1).TotalMilliseconds;
                        DBLog.Enqueue(new DBLogger() { ExecTime = dt1, Procedure = StoredProcName, TimeTaken = tt, Exception = Exec });
                    }
                    return ds;
                }
            }
        }

        public static SqlParameter SetValueDecimal(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToDecimal(value.ToString());
            }

            return sparam;
        }

        public static SqlParameter SetValueBool(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToBoolean(value.ToString());
            }

            return sparam;
        }
        public static SqlParameter SetValueSmallInt(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToInt16(value.ToString());
            }

            return sparam;
        }
        public static string GetValue(string str)
        {
            string MyValue = "";
            DataSet ds = GetData(str);
            if (ds != null)
            {
                MyValue = ds.Tables[0].Rows[0][0].ToString();
            }
            return MyValue;
        }

        public static void ExecuteNonQuery(string sql)
        {
            SqlConnection conn = new SqlConnection(GetDBConn());
            conn.Open();
            sql = sql.Replace("\r\n", " ");
            SqlCommand cmd = new SqlCommand(sql, conn);
            cmd.CommandTimeout = 0;
            cmd.ExecuteNonQuery();
            conn.Close();
        }

        public static DataSet GetData(string sql)
        {

            DataSet ds = new DataSet();
            try
            {

                SqlConnection conn = new SqlConnection(GetDBConn());
                conn.Open();

                sql = sql.Replace("\r\n", " ");
                SqlDataAdapter da = new SqlDataAdapter(sql, conn);
                //da.UpdateCommand.CommandTimeout = 120;
                da.Fill(ds);
                if (conn.State == ConnectionState.Open)
                    conn.Close();
                if (ds.Tables[0].Rows.Count == 0)
                    return null;
            }
            catch (Exception eex)
            {

            }
            return ds;
        }
        public static SqlParameter SetValueTinyInt(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToByte(Convert.ToInt32(value));
            }

            return sparam;
        }
        public static SqlParameter SetValueInt(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToInt32(value.ToString());
            }

            return sparam;
        }
        public static SqlParameter SetValueBigInt(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = Convert.ToInt64(value.ToString());
            }

            return sparam;
        }
        public static SqlParameter SetValueDateTime(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = DateTime.Parse(value.ToString());
            }
            return sparam;
        }
        public static SqlParameter SetValueGUID(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = (Guid)value;
            }
            return sparam;
        }
        public static SqlParameter SetValue(SqlParameter sparam, object value)
        {
            if (value == null)
            {
                sparam.Value = DBNull.Value;
            }
            else
            {
                sparam.Value = value;
            }
            return sparam;
        }

        public static SqlParameter[] CreateSQLParameterArray_Obselete(SqlParameter[] spa, SqlParameter sp)
        {
            Array.Resize(ref spa, spa.Length + 1);
            spa[spa.Length - 1] = sp;

            return spa;
        }

        public static string GetNewGUID()
        {
            return Guid.NewGuid().ToString();
        }


        private static void log_file(string message)
        {
            /* var sw = new System.IO.StreamWriter(filename, true);
             //  sw.WriteLine(DateTime.Now.ToString() + " " + e.Message + " " + e.InnerException);
             sw.WriteLine(DateTime.Now.ToString() + "\t" + message );
             sw.Close();*/
        }

    }

}