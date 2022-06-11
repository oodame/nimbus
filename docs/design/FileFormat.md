### 列存格式

#### 行列混存
在关系型数据库中，对于列存，业界大致有两种思路，一种是行列混存，一种是纯列存。

- 行列混存。将一张表的所有行，按照一定的规则，比如固定数量的行数，水平地进行分裂成若干组（Row Group），然后每一组内部的行数据再按照列进行重新聚合存储。这样的好处是一行的所有列都会存在于一个文件中，locality比较好。目前如Apache ORC/Parquet，Snowflake等等都采用了这种方式。学界最早提出这种存储方式的是PAX。

- 纯列存。纯列存则是将表的所有行，按照列进行重新聚合，以列的维度来存储。对于某一列数据，仍然可以按照固定行数进行分组。这样，一行的数据那么就有可能分散在不同的文件中，好处是对于全表扫描某一列的纯分析类任务相对友好。业界采用这种存储方式的有Vertica，Greenplum等等。

Nimbus的列存方案采用的是行列混存的模式，是由于其workload决定的：我们总是从一些点（vertex）出发，进行traverse（遍历点的出/入边），对边/对端点进行路径分析。因此，我们希望，一个点的出/入边能够尽量在一个文件中，这样遍历的效率最高。

另外，考虑到一个点的出/入边类型（type），所以参照关系型数据库中的方案，我们首先是确保一个点某种类型的出边/入边在一个EdgeGroup中。简单的方案就是，一个点的所有某个类型的出边，作为一个EdgeGroup。于是，我们有如下的EdgeGroup文件格式设计：

```text
+-----------+-------+-----------+-------+-----------+-------+ 
| Timestamp | DstId | Timestamp | DstId | Timestamp | DstId | \    
+-----------+-------+-----------+-------+-----------+-------+   Outgoing Edges Section 
|                           ...                             | / 
+----------+----------+------------+------------+-----------+ 
| Property | Property |  Property  |  Property  | Property  | \
+----------+----------+------------+------------+-----------+    Fixed Length Properties Section
|                           ...                             | /
+--------+--------+--------+--------------------------------+
| Offset | Offset | Offset |            ...                 | \
+--------+--------+--------+--------------------------------+   \
|   |         |       |                 ...                 |     \              
|   v         v       v                                     |     /  Variable Length Properties Section
+--------+--------+--------+--------------------------------+   /
| Value  | Value  | Value  |            ...                 | /
+--------+--------+--------+--------------------------------+
|                          ...                              |
|                                                           |
+----
| 
```
在EdgeGroup中，数据又分成了若干sections：outgoing edges, fixed length properties, variable length properties以及footer。

宏观上，

```text
Segment File
+-----------+
| EdgeGroup |
+-----------+
| EdgeGroup |
+-----------+
| EdgeGroup |
+-----------+
|    ...    |
+-----------+
| EdgeGroup |
+-----------+
```

```text
EdgeGroup Description Table
+---------------------+-------+----
| VertexId | EdgeType | SegNo | EdgeGroup
+
```

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



![Edge Group Format](design/images/edge_group.jpg)
![Edge Segment Format](design/images/edge_seg.png)
#### TODO
- [ ] What if a vertex has too many edges? How to split them?
- [ ] Null bit map
- [ ] Compression algorithm mark
