### 列存格式
---

#### 行列混存

在关系型数据库中，对于列存，业界大致有两种思路，一种是行列混存，一种是纯列存。

- 行列混存。将一张表的所有行，按照一定的规则，比如固定数量的行数，水平地进行分裂成若干组（Row Group），然后每一组内部的行数据再按照列进行重新聚合存储。这样的好处是一行的所有列都会存在于一个文件中，locality比较好。目前如Apache ORC/Parquet，Snowflake等等都采用了这种方式。学界最早提出这种存储方式的是PAX。

- 纯列存。纯列存则是将表的所有行，按照列进行重新聚合，以列的维度来存储。对于某一列数据，仍然可以按照固定行数进行分组。这样，一行的数据那么就有可能分散在不同的文件中，好处是对于全表扫描某一列的纯分析类任务相对友好。业界采用这种存储方式的有Vertica，Greenplum等等。

Nimbus的列存方案采用的是行列混存的模式，是由于其workload决定的：我们总是从一些点（vertex）出发，进行traverse（遍历点的出/入边），对边/端点进行路径分析。因此，我们希望，一个点的出/入边能够尽量在一个文件中，这样遍历的效率最高。

#### Overview Design

```text
Overview Design of Edge File Format
                                                                                                                           Compressed Section
                                                                                                                 +-------------+-------------+--------+
                                                                                                               / | Null bitmap | Value array | Footer |
VertexDispatch Table   AdjacentEdges          SegInfo File       EdgeGroupDesc File           Segment File   /   +-------------+-------------+--------+
     +--------+       +-------------+         +---------+    /   +----------------+          +-----------+ /     | Null bitmap | Value array | Footer |
     |   V1   |       | Out/In Edge |    /--> | SegInfo |   /    | EdgeGroup Desc |   --->   | EdgeGroup |       +-------------+-------------+--------+
     +--------+       +-------------+   /     +---------+  /     +----------------+          +-----------+ \     |                                    |
     |   V2   |       | Out/In Edge |  /      | SegInfo | /      | EdgeGroup Desc |   --->   | EdgeGroup |   \   |                 ....               |
     +--------+       +-------------+ /       +---------+/       +----------------+          +-----------+     \ +-------------+-------------+--------+
V -> |   V3   |  -->  | Out/In Edge | ------> | SegInfo |        | EdgeGroup Desc |   --->   | EdgeGroup |       | Null bitmap | Value array | Footer |
     +--------+       +-------------+ \       +---------+\       +----------------+          +-----------+       +-------------+-------------+--------+
     |   ...  |       |     ...     |  \      |   ...   | \      |      ...       |          |    ...    |
     +--------+       +-------------+   \     +---------+  \     +----------------+          +-----------+
     |   Vn   |       | Out/In Edge |    \--> | SegInfo |   \    | EdgeGroup Desc |   --->   | EdgeGroup |
     +--------+       +-------------+         +---------+    \   +----------------+          +-----------+
     \                                                                            /          \                                                         /
      ----------------------------------------------------------------------------            ---------------------------------------------------------
                                   MetaInfo Table                                                                         Data Table
```

以上是边数据的文件设计，大体包含两个部分：MetaInfo Table和Data Table。DataTable存储了边的属性信息；而在这之上构建了多层的MetaInfo Table，用于快速地查找某个点的出/入边。点边的数据存储和索引类似，所以我们这里只探讨了Edge File的设计。

我们先从最下面存储属性数据的EdgeGroup开始。

#### EdgeGroup File

我们把一个点的某个type的出/入边划成一个或多个EdgeGroup，划成多个group的原因是可以统计一个group的各种信息，比如某个property的min/max值等等，由于predicate的快速过滤（例如timestamp的range）；但又不能划太多，这样meta信息太多，所以需要有个折中的数据（TODO: let's get this number with some experiments）。但能够保证的是，一个EdgeGroup中的schema是相同的（TODO: maybe？schema change?）。

然后按照column进行聚合，每个column聚合的数据称为一个section，然后对其进行压缩存储；多个EdgeGroup数据以append的方式形成一个文件，我们称之为SegmentFile。SegmentFile中的edge的type都是一样的。

总的来说，每个column（除了outgoing/incoming edge section，TODO: 也许我们可以将各个section的格式统一起来，edge section部分的bitmap用来表示边是否被删除，let's make it happen if everything is alright）都是由三部分组成：Null bitmap，Value array以及Footer。下面的表格详细描述了未压缩前的各个section所包含的信息

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

我们按照schema的顺序依次将各个column聚合起来，但outgoing/incoming edges section总是位于Group的最前面。其中，各字段的意思如下

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

宏观上，一组EdgeGroup组成了一个segment file。

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

> 如何组织segment中的EdgeGroup？不同的方式，产生了不同的方案。以上的整体设计都是基于方案一设计的，这里我们稍微进行探讨一下
>
> - 方案一
>
> ```text    
>            +----------------+
>         /  | Segment File 1 | --> EdgeType 1
>      /     +----------------+
>    /       | Segment File 2 | --> EdgeType 2
> V          +----------------+
>    \       |       ...      |
>      \     +----------------+
>        \   | Segment File N | --> EdgeType N
>            +----------------+
> 
> ```
> 
> 对于某个点的出边来说（入边类似），按照其type，分布在不同的segment file中。简单起见，假如某个type的边都存在一个segment file中，V的出边共有EdgeType(1-N)，那么其出边将存在于segment file(1-N)中。
>
> 这样设计的好处是，同一个SegmentFile中的边schema都是相同的，关于column的信息好管理；不好的地方就在于V的边需要在多个SegmentFile中去查找。
>
> - 方案二
>
> ```text
>                                    EdgeType 1
>                                 /  
>            +----------------+ /    EdgeType 2
> V ---->    | Segment File 1 |      
>            +----------------+ \       ...
>            | Segment File 2 |   \       
>            +----------------+      EdgeType N
>            |       ...      |
>            +----------------+
>            | Segment File N |      
>            +----------------+
> ```
> 
> 对于某个点的出边来说，将其出边都存在一个segment file里面，再按照edge type进行聚合。这样做不好的地方在于会存在点数\*EdgeTypeNum份schema信息；好处是locality比较好（但这个存疑，也许不一定）
> 
> 总体来说还是倾向于方案一，因为业务总是会写明edge type，也有利于多线程处理（因为分布在不同的SegmentFile中，可以并行处理）。

#### EdgeGroupDesc File

说完了DataTable：EdgeGroup和SegmentFile，接下来我们来看看MetaInfo Table的设计。

有了EdgeGroup，我们需要有另外的文件（TODO:也可以直接放在SegmentFile里面，这里参照了KeyStone的设计）来存储其meta信息，这个文件叫做EdgeGroupDesc File。

```text
                                                                                   Compressed Section
                                                                         +-------------+-------------+--------+
                                                                       / | Null bitmap | Value array | Footer |
              EdgeGroupDesc File                      Segment File   /   +-------------+-------------+--------+
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
+-------------------+-------------------+-------------+------------+-------------+
| ColumnId(-1)      | ColumnId(0)       | ColumnId(1) |    ...     | ColumnId(m) |
+-------------------+-------------------+-------------+------------+-------------+
| EdgeColInfoOffset | PropColInfoOffset |   EdgeNum   |   StartTs  |    EndTs    |
+-------------------+-------------------+-------------+------------+-------------+
|    FileOffset     |                    DelBitmap                               | 
+-------------------+------------------------------------------------------------+
|     SecInfo       |                      Stats                                 |
+-------------------+------------------------------------------------------------+
|     SecInfo       |                      Stats                                 |
+-------------------+------------------------------------------------------------+
|     SecInfo       |                      Stats                                 |
+-------------------+------------------------------------------------------------+
|                                           ...                                  |
|                                                                                |
+-------------------+------------------------------------------------------------+
|     SecInfo       |                      Stats                                 |
+-------------------+------------------------------------------------------------+
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

ColumnId为负数表示特殊的column（这里我们用-1表示Outgoing edge）。负数的这一列存储了特殊的信息，包括EdgeGroup的边的数量；边的timestamp range，这对于skip时间查询条件和过期数据十分有效。每个column都对应了一个SecInfo，记录了column对应的section的信息。

TODO: naybe we can put DelBitmap into edge section.放在这里的好处是，我们总是要load这部分数据到内存中，所以可以提前做一些事情？这里没有想太清楚。

SecInfo记录了column对应section的信息，具体如下

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

接下来我们关心的是，给定一个点及其出边的type，如何快速找到相应数据？

```text
                                                                                                                           Compressed Section
                                                                                                                 +-------------+-------------+--------+
                                                                                                               / | Null bitmap | Value array | Footer |
VertexDispatch Table   AdjacentEdges          SegInfo File       EdgeGroupDesc File           Segment File   /   +-------------+-------------+--------+
     +--------+       +-------------+         +---------+    /   +----------------+          +-----------+ /     | Null bitmap | Value array | Footer |
     |   V1   |       | Out/In Edge |    /--> | SegInfo |   /    | EdgeGroup Desc |   --->   | EdgeGroup |       +-------------+-------------+--------+
     +--------+       +-------------+   /     +---------+  /     +----------------+          +-----------+ \     |                                    |
     |   V2   |       | Out/In Edge |  /      | SegInfo | /      | EdgeGroup Desc |   --->   | EdgeGroup |   \   |                 ....               |
     +--------+       +-------------+ /       +---------+/       +----------------+          +-----------+     \ +-------------+-------------+--------+
V -> |   V3   |  -->  | Out/In Edge | ------> | SegInfo |        | EdgeGroup Desc |   --->   | EdgeGroup |       | Null bitmap | Value array | Footer |
     +--------+       +-------------+ \       +---------+\       +----------------+          +-----------+       +-------------+-------------+--------+
     |   ...  |       |     ...     |  \      |   ...   | \      |      ...       |          |    ...    |
     +--------+       +-------------+   \     +---------+  \     +----------------+          +-----------+
     |   Vn   |       | Out/In Edge |    \--> | SegInfo |   \    | EdgeGroup Desc |   --->   | EdgeGroup |
     +--------+       +-------------+         +---------+    \   +----------------+          +-----------+
     \                                                                            /          \                                                         /
      ----------------------------------------------------------------------------            ---------------------------------------------------------
                                   MetaInfo File                                                                         Data File
```

- SegInfo File

SegInfo File中记录了一个SegmentFile的各个EdgeGroup的Offset数据，如下所示。

```text
SegInfo
+---------+-------+--------------+----------+---------+------------+
| Version | SegNo | EdgeGroupNum | FileSize | EdgeNum | DelEdgeNum |
+---------+-------+--------------+----------+---------+------------+
|                 EdgeGroupDesc Offset Array                       |
+------------------------------------------------------------------+
```

另外，我们需要一个vertex dispatch表，告诉vertext应该去哪些segment file的哪些edge group里去遍历边和属性。这个结构应该是可以常驻在内存中的（let's figure this out later）。这里我们假定VertexId是固定长度的，不定长的话加一个offset array即可。

```text
VertexDispath Table
+---------+-----------+----------+----------+-----+----------+
| Version | VertexNum | VertexId | VertexID | ... | VertexId |
+---------+-----------+----------+----------+-----+----------+
|             AdjacentEdges Table Offset Array               |
+------------------------------------------------------------+


Adjacent Edges Table
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+
| Outgoing Edge | SegNum | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId | ... | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId |
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+
| Incoming Edge | SegNum | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId | ... | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId |
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+
|                                                             ...                                                                              |
|                                                                                                                                              |
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+
| Outgoing Edge | SegNum | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId | ... | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId |
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+
| Incoming Edge | SegNum | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId | ... | SegNo | SegOffset | StartEdgeGroupId | EndEdgeGroupId |
+---------------+--------+-------+-----------+------------------+----------------+-----+-------+-----------+------------------+----------------+

```

以上两个Table可以合在一起，是用来查找一个点的出入边的SegInfo。

SegNo可以弄成`uin64_t`，地位4byte存储EdgeType，高位4byte存储SegFile ID

```text
+--------------------+------------------+
| SegFile Id(4 Byte) | EdgeType(4 Byte) |
+--------------------+------------------+
```

关于各个ID如何设计，也是可以继续挖掘的，可以设计出十分方便检索的结构。

以上是一个粗略版的Nimubus File Format Design。(Let's mark this day! June 12! Wow)

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
