# HBase ruby classes.
# Has wrapper classes for org.apache.hadoop.hbase.client.HBaseAdmin
# and for org.apache.hadoop.hbase.client.HTable.  Classes take
# Formatters on construction and outputs any results using
# Formatter methods.  These classes are only really for use by
# the hirb.rb HBase Shell script; they don't make much sense elsewhere.
# For example, the exists method on Admin class prints to the formatter
# whether the table exists and returns nil regardless.
include Java
import org.apache.hadoop.hbase.client.HBaseAdmin
import org.apache.hadoop.hbase.client.HTable
import org.apache.hadoop.hbase.HConstants
import org.apache.hadoop.hbase.io.BatchUpdate
import org.apache.hadoop.hbase.io.RowResult
import org.apache.hadoop.hbase.io.Cell
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.HColumnDescriptor
import org.apache.hadoop.hbase.HTableDescriptor
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.hbase.util.Writables

module HBase
  COLUMN = "COLUMN"
  COLUMNS = "COLUMNS"
  TIMESTAMP = "TIMESTAMP"
  NAME = HConstants::NAME
  VERSIONS = HConstants::VERSIONS
  STOPROW = "STOPROW"
  STARTROW = "STARTROW"
  ENDROW = STOPROW
  LIMIT = "LIMIT"

  # Wrapper for org.apache.hadoop.hbase.client.HBaseAdmin
  class Admin
    def initialize(configuration, formatter)
      @admin = HBaseAdmin.new(configuration)
      @formatter = formatter
    end
   
    def list
      now = Time.now 
      @formatter.header()
      for t in @admin.listTables()
        @formatter.row([t.getNameAsString()])
      end
      @formatter.footer(now)
    end

    def describe(tableName)
      now = Time.now 
      @formatter.header()
      found = false
      for t in @admin.listTables()
        if t.getNameAsString() == tableName
          @formatter.row([t.to_s])
          found = true
        end
      end
      if not found
        raise ArgumentError.new("Failed to find table named " + tableName)
      end
      @formatter.footer(now)
    end

    def exists(tableName)
      now = Time.now 
      @formatter.header()
      e = @admin.tableExists(tableName)
      @formatter.row([e.to_s])
      @formatter.footer(now)
    end

    def enable(tableName)
      # TODO: Need an isEnabled method
      now = Time.now 
      @admin.enableTable(tableName)
      @formatter.header()
      @formatter.footer(now)
    end

    def disable(tableName)
      # TODO: Need an isDisabled method
      now = Time.now 
      @admin.disableTable(tableName)
      @formatter.header()
      @formatter.footer(now)
    end

    def drop(tableName)
      now = Time.now 
      @admin.deleteTable(tableName)
      @formatter.header()
      @formatter.footer(now)
    end

    # Pass tablename and an array of Hashes
    def create(tableName, args)
      now = Time.now 
      # Pass table name and an array of Hashes.  Later, test the last
      # array to see if its table options rather than column family spec.
      raise TypeError.new("Table name must be of type String") \
        unless tableName.instance_of? String
      # For now presume all the rest of the args are column family
      # hash specifications. TODO: Add table options handling.
      htd = HTableDescriptor.new(tableName)
      for arg in args
        if arg.instance_of? String
          htd.addFamily(HColumnDescriptor.new(makeColumnName(arg)))
        else
          raise TypeError.new(arg.class.to_s + " of " + arg.to_s + " is not of Hash type") \
            unless arg.instance_of? Hash
          htd.addFamily(hcd(arg))
        end
      end
      @admin.createTable(htd)
      @formatter.header()
      @formatter.footer(now)
    end

    def alter(tableName, args)
      now = Time.now 
      raise TypeError.new("Table name must be of type String") \
        unless tableName.instance_of? String
      descriptor = hcd(args)
      @admin.modifyColumn(tableName, descriptor.getNameAsString(), descriptor);
      @formatter.header()
      @formatter.footer(now)
    end

    # Make a legal column  name of the passed String
    # Check string ends in colon. If not, add it.
    def makeColumnName(arg)
      index = arg.index(':')
      if not index
        # Add a colon.  If already a colon, its in the right place,
        # or an exception will come up out of the addFamily
        arg << ':'
      end
      arg
    end

    def hcd(arg)
      # Return a new HColumnDescriptor made of passed args
      # TODO: This is brittle code.
      # Here is current HCD constructor:
      # public HColumnDescriptor(final byte [] columnName, final int maxVersions,
      # final CompressionType compression, final boolean inMemory,
      # final boolean blockCacheEnabled,
      # final int maxValueLength, final int timeToLive,
      # BloomFilterDescriptor bloomFilter)
      name = arg[NAME]
      raise ArgumentError.new("Column family " + arg + " must have a name") \
        unless name
      name = makeColumnName(name)
      # TODO: What encoding are Strings in jruby?
      return HColumnDescriptor.new(name.to_java_bytes,
        # JRuby uses longs for ints. Need to convert.  Also constants are String 
        arg[VERSIONS]? arg[VERSIONS]: HColumnDescriptor::DEFAULT_VERSIONS,
        arg[HColumnDescriptor::COMPRESSION]? HColumnDescriptor::CompressionType::valueOf(arg[HColumnDescriptor::COMPRESSION]):
          HColumnDescriptor::DEFAULT_COMPRESSION,
        arg[HColumnDescriptor::IN_MEMORY]? arg[HColumnDescriptor::IN_MEMORY]: HColumnDescriptor::DEFAULT_IN_MEMORY,
        arg[HColumnDescriptor::BLOCKCACHE]? arg[HColumnDescriptor::BLOCKCACHE]: HColumnDescriptor::DEFAULT_BLOCKCACHE,
        arg[HColumnDescriptor::LENGTH]? arg[HColumnDescriptor::LENGTH]: HColumnDescriptor::DEFAULT_LENGTH,
        arg[HColumnDescriptor::TTL]? arg[HColumnDescriptor::TTL]: HColumnDescriptor::DEFAULT_TTL,
        arg[HColumnDescriptor::BLOOMFILTER]? arg[HColumnDescriptor::BLOOMFILTER]: HColumnDescriptor::DEFAULT_BLOOMFILTER)
    end
  end

  # Wrapper for org.apache.hadoop.hbase.client.HTable
  class Table
    def initialize(configuration, tableName, formatter)
      @table = HTable.new(configuration, tableName)
      @formatter = formatter
    end

    # Delete a cell
    def delete(row, args)
      now = Time.now 
      bu = nil
      if timestamp
        bu = BatchUpdate.new(row, timestamp)
      else
        bu = BatchUpdate.new(row)
      end
      bu.delete(column)
      @table.commit(bu)
      @formatter.header()
      @formatter.footer(now)
    end

    def deleteall(row, column = nil, timestamp = HConstants::LATEST_TIMESTAMP)
      now = Time.now 
      @table.deleteAll(row, column, timestamp)
      @formatter.header()
      @formatter.footer(now)
    end

    def deletefc(row, column_family, timestamp = HConstants::LATEST_TIMESTAMP)
      now = Time.now 
      @table.deleteFamily(row, column_family)
      @formatter.header()
      @formatter.footer(now)
    end

    def getAllColumns
       htd = @table.getMetadata()
       result = []
       for f in htd.getFamilies()
         n = f.getNameAsString()
         n << ':'
         result << n
       end
       result
    end

    def scan(columns, args = {})
      now = Time.now 
      if not columns or columns.length < 1
        # Make up list of columns.
        columns = getAllColumns()
      end
      if columns.class == String
        columns = [columns]
      end
      cs = columns.to_java(java.lang.String)
      limit = -1
      if args == nil or args.length <= 0
        s = @table.getScanner(cs)
      else
        limit = args["LIMIT"] || -1 
        filter = args["FILTER"] || nil
        startrow = args["STARTROW"] || ""
        stoprow = args["STOPROW"] || nil
        timestamp = args["TIMESTAMP"] || HConstants::LATEST_TIMESTAMP
        if stoprow
          s = @table.getScanner(cs, startrow, stoprow, timestamp)
        else
          s = @table.getScanner(cs, startrow, timestamp, filter) 
        end
      end 
      count = 0
      @formatter.header(["ROW", "COLUMN+CELL"])
      i = s.iterator()
      while i.hasNext()
        r = i.next()
        row = String.from_java_bytes r.getRow()
        for k, v in r
          column = String.from_java_bytes k
          cell = toString(column, v)
          @formatter.row([row, "column=%s, %s" % [column, cell]])
        end
        count += 1
        if limit != -1 and count >= limit
          break
        end
      end
      @formatter.footer(now)
    end

    def put(row, column, value, timestamp = nil)
      now = Time.now 
      bu = nil
      if timestamp
        bu = BatchUpdate.new(row)
      else
        bu = BatchUpdate.new(row)
      end
      bu.put(column, value.to_java_bytes)
      @table.commit(bu)
      @formatter.header()
      @formatter.footer(now)
    end

    def isMetaTable()
      tn = @table.getTableName()
      return Bytes.equals(tn, HConstants::META_TABLE_NAME) or
        Bytes.equals(tn, HConstants::META_TABLE_NAME)
        
    end

    # Make a String of the passed cell.
    # Intercept cells whose format we know such as the info:regioninfo in .META.
    def toString(column, cell)
      if isMetaTable()
        if column == 'info:regioninfo'
          hri = Writables.getHRegionInfoOrNull(cell.getValue())
          return "timestamp=%d, value=%s" % [cell.getTimestamp(), hri.toString()]
        elsif column == 'info:serverstartcode'
          return "timestamp=%d, value=%s" % [cell.getTimestamp(), \
            Bytes.toLong(cell.getValue())]
        end
      end
      cell.toString()
    end
  
    # Get from table
    def get(row, args = {})
      now = Time.now 
      result = nil
      if args == nil or args.length == 0
        result = @table.getRow(row.to_java_bytes)
      else
        # Its a hash.
        columns = args[COLUMN] 
        if columns == nil
          # Maybe they used the COLUMNS key
          columns = args[COLUMNS]
        end
        if columns == nil
          # May have passed TIMESTAMP and row only; wants all columns from ts.
          ts = args[TIMESTAMP] 
          if not ts
            raise ArgumentError.new("Failed parse of " + args + ", " + args.class)
          end
          result = @table.getRow(row.to_java_bytes, ts)
        else
          # Columns are non-nil
          if columns.class == String
            # Single column
            result = @table.get(row, columns,
              args[TIMESTAMP]? args[TIMESTAMP]: HConstants::LATEST_TIMESTAMP,
              args[VERSIONS]? args[VERSIONS]: 1)
          elsif columns.class == Array
            result = @table.getRow(row, columns.to_java(:string),
              args[TIMESTAMP]? args[TIMESTAMP]: HConstants::LATEST_TIMESTAMP)
          else
            raise ArgumentError.new("Failed parse column argument type " +
              args + ", " + args.class)
          end
        end
      end
      # Print out results.  Result can be Cell or RowResult.
      h = nil
      if result.instance_of? RowResult
        h = String.from_java_bytes result.getRow()
        @formatter.header(["COLUMN", "CELL"])
        if result
          for k, v in result
            column = String.from_java_bytes k
            @formatter.row([column, toString(column, v)])
          end
        end
      else
        # Presume Cells
        @formatter.header()
        if result 
          for c in result
            @formatter.row([c.toString()])
          end
        end
      end
      @formatter.footer(now)
    end
  end

  # Testing. To run this test, there needs to be an hbase cluster up and
  # running.  Then do: ${HBASE_HOME}/bin/hbase org.jruby.Main bin/HBase.rb
  if $0 == __FILE__
    # Add this directory to LOAD_PATH; presumption is that Formatter module
    # sits beside this one.  Then load it up.
    $LOAD_PATH.unshift File.dirname($PROGRAM_NAME)
    require 'Formatter'
    # Make a console formatter
    formatter = Formatter::Console.new(STDOUT)
    # Now add in java and hbase classes
    configuration = HBaseConfiguration.new()
    admin = Admin.new(configuration, formatter)
    # Drop old table.  If it does not exist, get an exception.  Catch and
    # continue
    TESTTABLE = "HBase_rb_testtable"
    begin
      admin.disable(TESTTABLE)
      admin.drop(TESTTABLE)
    rescue org.apache.hadoop.hbase.TableNotFoundException
      # Just suppress not found exception
    end
    admin.create(TESTTABLE, [{NAME => 'x', VERSIONS => 5}])
    # Presume it exists.  If it doesn't, next items will fail.
    table = Table.new(configuration, TESTTABLE, formatter) 
    for i in 1..10
      table.put('x%d' % i, 'x:%d' % i, 'x%d' % i)
    end
    table.get('x1', {COLUMN => 'x:1'})
    if formatter.rowCount() != 1
      raise IOError.new("Failed first put")
    end
    table.scan(['x:'])
    if formatter.rowCount() != 10
      raise IOError.new("Failed scan of expected 10 rows")
    end
    # Verify that limit works.
    table.scan(['x:'], {LIMIT => 3})
    if formatter.rowCount() != 3
      raise IOError.new("Failed scan of expected 3 rows")
    end
    # Should only be two rows if we start at 8 (Row x10 sorts beside x1).
    table.scan(['x:'], {STARTROW => 'x8', LIMIT => 3})
    if formatter.rowCount() != 2
      raise IOError.new("Failed scan of expected 2 rows")
    end
    # Scan between two rows
    table.scan(['x:'], {STARTROW => 'x5', ENDROW => 'x8'})
    if formatter.rowCount() != 3
      raise IOError.new("Failed endrow test")
    end
    admin.disable(TESTTABLE)
    admin.drop(TESTTABLE)
  end
end