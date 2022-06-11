### 列存格式
---

#### 行列混存

在关系型数据库中，对于列存，业界大致有两种思路，一种是行列混存，一种是纯列存。

- 行列混存。将一张表的所有行，按照一定的规则，比如固定数量的行数，水平地进行分裂成若干组（Row Group），然后每一组内部的行数据再按照列进行重新聚合存储。这样的好处是一行的所有列都会存在于一个文件中，locality比较好。目前如Apache ORC/Parquet，Snowflake等等都采用了这种方式。学界最早提出这种存储方式的是PAX。

- 纯列存。纯列存则是将表的所有行，按照列进行重新聚合，以列的维度来存储。对于某一列数据，仍然可以按照固定行数进行分组。这样，一行的数据那么就有可能分散在不同的文件中，好处是对于全表扫描某一列的纯分析类任务相对友好。业界采用这种存储方式的有Vertica，Greenplum等等。

Nimbus的列存方案采用的是行列混存的模式，是由于其workload决定的：我们总是从一些点（vertex）出发，进行traverse（遍历点的出/入边），对边/端点进行路径分析。因此，我们希望，一个点的出/入边能够尽量在一个文件中，这样遍历的效率最高。

另外，考虑到一个点的出/入边类型（type），所以参照关系型数据库中的方案，我们首先是确保一个点某种类型的出边/入边在一个EdgeGroup中。简单的方案就是，一个点的所有某个类型的出边，作为一个EdgeGroup。

#### EdgeGroup File

于是，我们有如下的EdgeGroup文件格式设计：

```text

+-----------+-------+-----------+-------+-----------+----------+ 
| Timestamp | DstId | Timestamp | DstId | Timestamp | DstId    | \    
+-----------+-------+-----------+-------+-----------+----------+   Outgoing Edges Section 
|                           ...                                | /                                                   
+-------------+----------+------------+------------+-----------+ 
| Null Bitmap | Property |  Property  |  Property  | Property  | \
+-------------+----------+------------+------------+-----------+    Fixed Length Properties Section
|                           ...                    |   Footer  | /
+-------------+--------+--------+--------+---------+-----------+
| NUll Bitmap | Offset | Offset | Offset |       ...           | \
+-------------+--------+--------+--------+---------------------+   \
|                 |         |       |             ...          |     \              
|                 v         v       v                          |     /  Variable Length Properties Section
+-------------+--------+--------+--------+------------+--------+   /
|    ...      |  Value | Value  | Value  |  ...       | Footer | /
+-------------+--------+--------+--------+------------+--------+
|                          ...                                 |
|                                                              |
+--------------------------------------------------------------+
```
在EdgeGroup中，数据又分成了若干sections：outgoing edges, fixed length properties, variable length properties。其中，各字段的意思如下

```text
+-------------+--------------------+------------------------------------------------------+
|    Field    |     Size(Bytes)    |                       Desc                           |
+-------------+--------------------+------------------------------------------------------+
|  Timestamp  |         8          | Timestamp of an edge                                 |
+-------------+--------------------+------------------------------------------------------+
|     DstId   |         8          | Destination id of an edge                            |                 
+-------------+--------------------+------------------------------------------------------+
|             |                    | Indicates wherther an property values exists or not  |
| Null Bitmap | aligned(edgeNum/8) | (only exists when footer[0] & 0x10 == 1)             |
|             |                    |                                                      |
+-------------+--------------------+------------------------------------------------------+
|   Property  |       1/2/4/8      | Fixed length properties, with a length of 1/2/4/8    |
+-------------+--------------------+------------------------------------------------------+
|   Offset    |         4          | Offset a value in this section                       |
+-------------+--------------------+------------------------------------------------------+
|             |                    | byte[0] | 0x11 = [0: all 0 | 1: all 1 | others]      |
|             |                    | if byte[0] | 0x11 == 0 or 1, we do not store the     | 
|             |                    | bitmap;                                              |
|             |                    | byte[0] most significant 6 bits indicates which      |
|             |                    | compression algorithm is used to compress null       | 
|             |                    | bitmap;                                              |
|    Footer   |         8          | byte[1] stands for which compression algorithm is    |
|             |                    | applied to compression value array;                  |
|             |                    | byte[2,3] byte[2] & 0x01 indcates checksum is used   |
|             |                    | or not; the next least bit represents endianness;    |
|             |                    | (others are reserved)                                | 
|             |                    | byte[4-7] stores CRC32checksum (null bitmap and      |
|             |                    | value array)                                         |     
+-------------+--------------------+------------------------------------------------------+
```

宏观上，一组EdgeGroup组成了一个segment file。如何组织segment中的EdgeGroup？不同的方式，产生了不同的方案。

```text
                              Compressed Section
                    +-------------+-------------+--------+
                  / | Null bitmap | Value array | Footer |
 Segment File   /   +-------------+-------------+--------+
+-----------+ /     +-------------+-------------+--------+
| EdgeGroup |       | Null bitmap | Value array | Footer |
+-----------+ \     +-------------+-------------+--------+
| EdgeGroup |   \                   ....
+-----------+     \ +-------------+-------------+--------+
| EdgeGroup |       | Null bitmap | Value array | Footer |
+-----------+       +-------------+-------------+--------+
|    ...    |
+-----------+
| EdgeGroup |
+-----------+
```

#### Segment File

- 方案一

```text    
           +----------------+
        /  | Segment File 1 | --> EdgeType 1
     /     +----------------+
   /       | Segment File 2 | --> EdgeType 2
V          +----------------+
   \       |       ...      |
     \     +----------------+
       \   | Segment File N | --> EdgeType N
           +----------------+

```

对于某个点的出边来说（入边类似），按照其type，分布在不同的segment file中。简单起见，假如某个type的边都存在一个segment file中，V的出边共有EdgeType(1-N)，那么其出边将存在于segment file(1-N)中。

```text
                                                                                   Compressed Section
                                                                         +-------------+-------------+--------+
                                                                       / | Null bitmap | Value array | Footer |
                 SegInfo File                         Segment File   /   +-------------+-------------+--------+
              +----------------+                     +-----------+ /     +-------------+-------------+--------+
              | EdgeGroup Desc |     -------->       | EdgeGroup |       | Null bitmap | Value array | Footer |
              +----------------+                     +-----------+ \     +-------------+-------------+--------+
              | EdgeGroup Desc |     -------->       | EdgeGroup |   \                   ....
              +----------------+                     +-----------+     \ +-------------+-------------+--------+
              | EdgeGroup Desc |     -------->       | EdgeGroup |       | Null bitmap | Value array | Footer |
              +----------------+                     +-----------+       +-------------+-------------+--------+
              |      ...       |                     |    ...    |
              +----------------+                     +-----------+
              | EdgeGroup Desc |     -------->       | EdgeGroup |
              +----------------+                     +-----------+
```

对于含有m个property的edge type来说，一个EdgeGroup的desc table如下所示（这里也许我们可以偷懒，用一个成熟的KV存储，以<CentreId,SegNo,ColumnId>为key）

```text
EdgeGroup Desc Table
+--------------+-------------+-------------+------------+-------------+
| ColumnId(-1) | ColumnId(0) | ColumnId(1) |    ...     | ColumnId(m) |
+--------------+-------------+-------------+------------+-------------+
|  EdgeColInfoOffset         |      PropColInfoOffset                 |
+--------------+-------------+-------------+------------+-------------+
|    EdgeNum   | StartTs     | EndTs       | FileOffset |  DelBitmap  | 
+--------------+-------------+-------------+------------+-------------+
|    SecInfo   |                          Stats                       |
+--------------+------------------------------------------------------+
|    SecInfo   |                          Stats                       |
+--------------+------------------------------------------------------+
|    SecInfo   |                          Stats                       |
+--------------+------------------------------------------------------+
|                               ...                                   |
|                                                                     |
+--------------+------------------------------------------------------+
|    SecInfo   |                          Stats                       |
+--------------+------------------------------------------------------+
```

这里麻烦一点的做法是记录每个SecInfo对应在EdgeDesc table中的offset。简单一点的做法是，让每个column对应的meta info保持一样的大小。上表中采取的是麻烦一点的做法，可以节省一些存储空间（其实只有ColumnId为负数的Column对应的info和其它column不一样，其它都相同，所以上表记两个offset即可）。其中，各字段代表的意义如下

```text
+-------------------+--------------------+-----------------------------------------------------------+
|   Field           |     Size(Bytes)    |                           Desc                            |
+-------------------+--------------------+-----------------------------------------------------------+
| ColumnId          |          4         | Id of a column; negtive columns stands for special ones   |
+-------------------+--------------------+-----------------------------------------------------------+
| EdgeColInfoOffset |          4         | Edge column info offset in this EdgeGroup desc file       |
+-------------------+--------------------+-----------------------------------------------------------+
| PropColInfoOffset |          4         | Property column info offset in this EdgeGroup desc file   |
+-------------------+--------------------+-----------------------------------------------------------+
| EdgeNum           |          8         | Total number of edges in this group                       |
+-------------------+--------------------+-----------------------------------------------------------+
| StartTs           |          8         | Minimum timestmap in this group                           |
+-------------------+--------------------+-----------------------------------------------------------+
| EndTs             |          8         | Maximum timestamp in this group                           |
+-------------------+--------------------+-----------------------------------------------------------+
| FileOffset        |          8         | Offset of this group in segment file                      |
+-------------------+--------------------+-----------------------------------------------------------+
| DelBitmap         | aligned(edgeNum/8) | Indicates whether an edge in this group is deleted or not |
+-------------------+--------------------+-----------------------------------------------------------+
```

ColumnId为负数表示特殊的column（这里我们用-1表示Outgoing edge）。负数的这一列存储了特殊的信息，包括EdgeGroup的边的数量；边的timestamp range，这对于skip时间查询条件和过期数据十分有效。每个column都对应了一个SecInfo，记录了cloumn对应的section的信息。

```text
SecInfo
+---------+-------+--------------------+--------------------+------------------+-------------------+----------+
| Version | Flags | Null bitmap offset | Value array offset | Value array size | Uncompressed size | Checksum |
+---------+-------+--------------------+--------------------+------------------+-------------------+----------+

+--------------------+-------------+--------------------------------------------------------------------+
|       Field        | Size(Bytes) |                               Desc                                 |
+--------------------+-------------+--------------------------------------------------------------------+
| Version            |      1      | Indicates the sectction format version, for compatibility          |
+--------------------+-------------+--------------------------------------------------------------------+
| Flags              |      3      | Byte[0] ColumnType (others are reserved, column value type?)       |
+--------------------+-------------+--------------------------------------------------------------------+
| Null bitmap offset |      8      | Offset of the null bitmap in this group                            |
+--------------------+-------------+--------------------------------------------------------------------+
| Value array offset |      4      | Offset of the value array in this section                          |
+--------------------+-------------+--------------------------------------------------------------------+
| Value array size   |      8      | Size of the value array                                            |
+--------------------+-------------+--------------------------------------------------------------------+
| Uncompressed size  |      8      | Size of the null bitmap + value array before compressed            |
+--------------------+-------------+--------------------------------------------------------------------+
| Checksum           |      4      | CRC32 Checksum of null bitmap and value array(optional)            |
+--------------------+-------------+--------------------------------------------------------------------+
```

关于Stats字段并没有想好，也许只对数值类型的字段做stats，下面是一种想法。

```text
Stats
        ---------------------------------------
        |                                     |
        |                                     |
        |                                     v
      +---+---+---+---+---+---+---+---+     +---+---+---+---+---+---+---+---+                     +-----+-----+-----+
bits  | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |     | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |     padding maybe   | max | min | sum |
      +---+---+---+---+---+---+---+---+     +---+---+---+---+---+---+---+---+                     +-----+-----+-----+
                 Byte[0]                                Byte[1]                              
```

Stats头一个byte，bits 0-6 表示相应的stats是否激活，1表示激活，0表示未激活；高位表示下个byte是否还是stats激活byte，1表示是，0表示不是。（也许一个byte就够了，应该没有这么多种column的stats吧，maybe...）。紧接着的是相应的stats值，个数是前面的1的个数。

#### MetaInfo Tables

- SegInfo table




- VertexFanout table



```text
EdgeGroup Description Table
+----------+-----------+-------+---------------+------------------------+
| VertexId | EdgeType1 | SegNo | EdgeGroup Num | EdgeGroup Offset Array |
+----------+-----------+-------+---------------+------------------------+
```





- 方案二

```text
                                   EdgeType 1
                                /  
           +----------------+ /    EdgeType 2
V ---->    | Segment File 1 |      
           +----------------+ \       ...
           | Segment File 2 |   \       
           +----------------+      EdgeType N
           |       ...      |
           +----------------+
           | Segment File N |      
           +----------------+
```



### TODO
---
- [ ] What if a vertex has too many edges? How to split them?
- [ ] Null bit map
- [ ] Compression algorithm mark
- [ ] What if I store the data of all vertices in all machines?

### References
---
[1] KeyStone   
[2] ClickHouse   
[3] TiDB & TiFlash   
