# HRMS_Data.xlsx -> db/92_Import_HRMS_Data.sql

Builds the import script from the company workbook. The generated script
(`db/92_Import_HRMS_Data.sql`, kept in the db folder) carries personal data (civil
IDs, passports) - keep the repository private. The intermediate `data.json` and the
questions workbook are not kept in git (see `.gitignore`).

```bash
python3 -I read.py HRMS_Data.xlsx data.json            # the workbook -> json
python3 -I gen.py data.json header.sql body.sql \
        ../../92_Import_HRMS_Data.sql report.json      # the SQL (stops on anything unmapped)
python3 -I questions.py report.json HRMS_Import_Questions.xlsx   # what the sheet does not say
```

The mappings (companies, licence -> document type, authorities, vehicles, work
permit job -> designation, nationalities) are at the top of `gen.py`.
