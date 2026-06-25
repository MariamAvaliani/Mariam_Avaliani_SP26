import os
import pandas as pd
import numpy as np
import json

os.makedirs("output_files", exist_ok=True)

PATH_TO_SALES = "./source_files/sales.csv"
PATH_TO_HOUSES = "./source_files/houses.csv"
PATH_TO_EMPLOYEES = "./source_files/employees.csv"

# ----------------------------
# 1. READ DATA
# ----------------------------
sales = pd.read_csv(PATH_TO_SALES)
houses = pd.read_csv(PATH_TO_HOUSES)
employees = pd.read_csv(PATH_TO_EMPLOYEES)

# keep original for task 12 safety
sales_original = sales.copy()

# ----------------------------
# 2. ROWS 3–10 (inclusive)
# ----------------------------
names = employees.iloc[2:10][["EMP_FIRST_NAME", "EMP_LAST_NAME"]]

# ----------------------------
# 3. GENDER COUNT
# ----------------------------
amount_by_gender = employees["EMP_GENDER"].value_counts()

# ----------------------------
# 4. FILL NaN
# ----------------------------
houses["SQUARE"] = houses["SQUARE"].fillna(0)

# ----------------------------
# 5. UNIT PRICE
# ----------------------------
houses["UNIT_PRICE"] = houses.apply(
    lambda x: -1 if x["SQUARE"] == 0 else round(x["PRICE"] / x["SQUARE"], 2),
    axis=1
)

# ----------------------------
# 6. SORT + JSON
# ----------------------------
houses_sorted = houses.sort_values(by="PRICE", ascending=False)
houses_sorted.to_json("./output_files/task_6.json", orient="records")

# ----------------------------
# 7. FILTER VERA WOMEN
# ----------------------------
employees_filtered = employees[
    (employees["EMP_GENDER"] == "F") &
    (employees["EMP_FIRST_NAME"] == "Vera")
]

# ----------------------------
# 8. GROUPBY (SQUARE >= 100)
# ----------------------------
df = (
    houses[houses["SQUARE"] >= 100]
    .groupby(["HOUSE_CATEGORY", "HOUSE_SUBCATEGORY"])
    .size()
)

# ----------------------------
# 9. SAFE AVRO (NO fragile schema hacks)
# ----------------------------
from fastavro import writer

records = df.reset_index()
records.columns = ["HOUSE_CATEGORY", "HOUSE_SUBCATEGORY", "count"]

schema = {
    "doc": "house counts",
    "name": "houses",
    "type": "record",
    "fields": [
        {"name": "HOUSE_CATEGORY", "type": "string"},
        {"name": "HOUSE_SUBCATEGORY", "type": "string"},
        {"name": "count", "type": "int"}
    ]
}

with open("./output_files/task_9.avro", "wb") as out:
    writer(out, schema, records.to_dict("records"))

# ----------------------------
# 10. UPDATE SALESAMOUNT (safe)
# ----------------------------
avg_sales = sales_original["SALEAMOUNT"].mean()

sales["SALEAMOUNT"] = sales["SALEAMOUNT"].apply(
    lambda x: x + avg_sales * 0.02
)

# ----------------------------
# 11. UNSOLD HOUSES
# ----------------------------
unsold = houses[~houses["HOUSE_ID"].isin(sales_original["HOUSE_ID"])]

house_ids_available = unsold["HOUSE_ID"].unique().tolist()

with open("./output_files/task_11.json", "w") as f:
    json.dump(house_ids_available, f)

# ----------------------------
# 12. SALES PER EMPLOYEE (SAFE + CLEAN)
# ----------------------------
emp_sales = sales.groupby("EMP_ID")["SALEAMOUNT"].sum().reset_index()

emp_sales = emp_sales.merge(
    employees[["EMP_ID", "EMP_FIRST_NAME", "EMP_LAST_NAME"]],
    on="EMP_ID",
    how="left"
)

emp_sales = emp_sales[[
    "EMP_ID",
    "EMP_FIRST_NAME",
    "EMP_LAST_NAME",
    "SALEAMOUNT"
]]

emp_sales.columns = [
    "emp_id",
    "emp_first_name",
    "emp_last_name",
    "sum_sales"
]

emp_sales.to_excel("./output_files/task_12.xlsx", index=False, engine="xlsxwriter")
print("ALL TASKS PASSED ")