# HRMS_Data.xlsx -> db/92_Import_HRMS_Data.sql

Builds the import script from the company workbook. The generated script and the
questions workbook carry personal data (civil IDs, passports), so they are **not**
kept in git (see `.gitignore`); rebuild them from the workbook when needed.

```bash
python3 -I read.py HRMS_Data.xlsx data.json            # the workbook -> json
python3 -I gen.py data.json header.sql body.sql \
        ../../92_Import_HRMS_Data.sql report.json      # the SQL (stops on anything unmapped)
python3 -I questions.py report.json HRMS_Import_Questions.xlsx   # what the sheet does not say
```

The mappings (companies, licence -> document type, authorities, vehicles, work
permit job -> designation, nationalities) are at the top of `gen.py`.
