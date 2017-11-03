# These are the columns that YNAB expects
ynab_cols = ['Date','Payee','Category','Memo','Outflow','Inflow']

# Converts a string value into a number.
# Filters out all special characters like $ or ,
numberfy = (val) ->
  # Convert val into empty string if it is undefined or null
  if !val?
    val = ''
  if isNaN(val)
    # check for negative signs or parenthases.
    is_negative = if (val.match("-") || val.match(/\(.*\)/)) then -1 else 1
    # replace comma decimal separateor with dot
    val = val.replace(/,/g, ".")
    # return just the number and make it negative if needed.
    +(val.match(/\d+.?\d*/)[0]) * is_negative
  else
    val


#
# This method extracts the payee field from an ING statement row.
# The information about that payee has to be parsed out of different fields depending on transaction type.
#
parse_payee = (row) ->
  tmp_row_col = null
  # Make sure the description is readable
  if !row['Description']?
    console.log 'No Description:  '
    for key, value of row
      console.log key + ":  "  + value
  # For Maestro, extract the payee after the timestamp in the Description; for older transactions this was Entry Details
  else if row['Description'].match('Purchase Maestro')
    details = row['Description']
    startPos = details.match(/\s(a|p)m\s/).index + 6  # am or pm time
    endPos = details.indexOf(' - ', startPos)
    tmp_row_col =  details.substr(startPos, endPos-startPos)
  # For Bancontact, extract the payee after the timestamp in the Description
  else if row['Description'].match('Purchase Bancontact')
    details = row['Description']
    try
      startPos = details.match(/\s(a|p)m\s/).index + 6
      endPos = details.indexOf(" - ", startPos)
      tmp_row_col =  details.substr(startPos, endPos-startPos)
    catch e
      console.log 'No timestamp for Purchase Bancontact:  ' + details
      tmp_row_col =  details
  # For cash withdrawals, use 'Cash'
  else if row['Description'].match(/Cash (w|W)ithdrawal/)
    tmp_row_col = 'Cash'
  # ING charges
  else if row['Description'].match('Breakdown of charges')
    tmp_row_col = 'ING'
  # For transfers, use the value between From: and IBAN:
  else if row['Description'].match('European transfer')
    details = row['Entry Details']
    if row['Entry Details'].match(/European transfer\s*From:/)
      startPos = details.indexOf('From: ') + 6
      endPos = details.indexOf('IBAN:', startPos) - 1
      tmp_row_col =  details.substr(startPos, endPos-startPos)
    # ING Card repayment
    else if row['Entry Details'].match(/ING Smart Banking payment\s*In favour of:/)
      tmp_row_col =  row['Counterparty account']
    # ING Card repayment
    else if row['Entry Details'].match(/Message:\s*Repayment of your ING Card Account/)
      tmp_row_col =  row['Counterparty account']
    else if row['Entry Details'].match(/favour of:/)
      startPos = details.indexOf(' favour of: ') + 12
      endPos = details.indexOf('IBAN:', startPos) - 1
      tmp_row_col =  details.substr(startPos, endPos-startPos)
  # For Direct Debit, extact name
  else if row['Description'].match('European Direct Debit')
    details = row['Entry Details']
    startPos = details.indexOf(' for: ') + 6
    endPos = details.indexOf('Identication:', startPos) - 1
    tmp_row_col =  details.substr(startPos, endPos-startPos)
  # For Home'Bank memotransfer, extract name between To: and Message:
  else if row['Description'].match(/Home'Bank memotransfer\s*To:/)
    details = row['Description']
    startPos = details.indexOf(' To: ') + 5
    endPos = details.indexOf('Message:', startPos) - 1
    tmp_row_col =  details.substr(startPos, endPos-startPos)
  # For Visa repayments, use 'VISA'
  else if row['Description'].match(/ING : VISA\s*REF/)
    tmp_row_col = 'VISA'
  else
    tmp_row_col =  row['Counterparty account']
  return tmp_row_col


# This class does all the heavy lifting.
# It takes the and can format it into csv
class window.DataObject
  constructor: () ->
    @base_json = null

  # Parse base csv file as JSON. This will be easier to work with.
  # It uses http://papaparse.com/ for handling parsing
  parse_csv: (csv) -> @base_json = Papa.parse(csv, {"header": true})
  fields: -> @base_json.meta.fields
  rows: -> @base_json.data


  # This method converts base_json into a json file with YNAB specific fields based on
  #   which fields you choose in the dropdowns in the browser.
  #
  # --- parameters ----
  # limit: expects and integer and limits how many rows get parsed (specifically for preview)
  #     pass in false or null to do all.
  # lookup: hash definition of YNAB column names to selected base column names. Lets us
  #     convert the uploaded CSV file into the columns that YNAB expects.
  converted_json: (limit, lookup) ->
    return nil if @base_json == null
    value = []

    # TODO: You might want to check for errors. Papaparse has an errors field.
    if @base_json.data
      @base_json.data.forEach (row, index) ->
        if !limit || index < limit
          tmp_row = {}
          ynab_cols.forEach (col) ->
            cell = row[lookup[col]]
            #
            # Some YNAB columns need special formatting,
            #   the rest are just returned as they are.
            #
            switch col
              # Merge multiple CSV fields in the the Memo field
              when 'Payee'
                tmp_row[col] = parse_payee(row)
              when 'Memo'
                tmp_row[col] = row['Entry number'] + ' ' + row['Description']
              when 'Outflow'
                number = numberfy(cell)
                if lookup['Outflow'] == lookup['Inflow']
                  tmp_row[col] = Math.abs(number) if number < 0
                else
                  tmp_row[col] = number
              when 'Inflow'
                number = numberfy(cell)
                if lookup['Outflow'] == lookup['Inflow']
                  tmp_row[col] = number if number > 0
                else
                  tmp_row[col] = number
              else tmp_row[col] = cell

          value.push(tmp_row)
    value

  converted_csv: (limit, lookup) ->
    return nil if @base_json == null
    # Papa.unparse string
    string = ynab_cols.join(',') + "\n"
    @.converted_json(limit, lookup).forEach (row) ->
      row_values = []
      ynab_cols.forEach (col) ->
        row_values.push row[col]
      string += row_values.join(',') + "\n"
    string
