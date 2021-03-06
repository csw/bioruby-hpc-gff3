module bio.gff3.feature_range;

import bio.gff3.feature, bio.gff3.record, bio.gff3.validation;
import util.range_with_cache, util.dlist, util.string_hash;

/**
 * FeatureRange is a range of features from a range of records.
 * Use front, popFront() and empty for traversal.
 */
class FeatureRange : RangeWithCache!Feature {
  /**
   * Constructor of a range of features.
   * Params:
   *     records =             A range of records.
   *     feature_cache_size =  Cache size for features.
   *     link_features =       The parser will link features into parent-child relationships
   *                           if this parameter is true.
   */
  this(RangeWithCache!Record records, size_t feature_cache_size = 1000, bool link_features = false) {
    this.records = records;
    this.data = new FeatureCache(feature_cache_size, link_features);
  }

  protected Feature next_item() {
    Feature feature;
    while((!records.empty) && (feature is null)) {
      feature = data.add_record(records.front);
      records.popFront();
    }
    if ((feature is null) && (records.empty)) {
      feature = data.remove_from_back();
    }
    return feature;
  }

  private {
    RangeWithCache!Record records;
    FeatureCache data;
  }
}

private:

/**
 * Keeps the last max_size features in an array. That way there is
 * some buffer space for records which are at most max_size records
 * far from the last record which is part of the same feature.
 */
class FeatureCache {
    this(size_t max_size = 1000, bool link_features = false) {
    this.max_size = max_size;
    this.link_features = link_features;
    this.dlist = new DList!FeatureCacheItem();
    this.list = new FeatureCacheItem[max_size];
  }

  /**
   * If the feature with the same ID is already in the cache, this method
   * adds the new record to that feature and returns null. Otherwise it
   * adds a new feature to the cache and removes and returns the oldest
   * feature in the cache.
   */
  Feature add_record(Record new_record) {
    int record_hash = 0;
    if (new_record.id != null) {
      record_hash = hash(new_record.id);
      FeatureCacheItem * item = dlist.first;
      while(item !is null) {
        if (item.id_hash == record_hash) {
          if (item.feature.id == new_record.id) {
            item.feature.add_record(new_record);
            dlist.remove(item);
            dlist.insert_front(item);
            return null;
          }
        }
        item = item.next;
      }
    }
    auto new_item = FeatureCacheItem(record_hash, hash(new_record.parent), new Feature(new_record), null, null);
    Feature result;
    if (current_size != max_size) {
      list[current_size] = new_item;
      dlist.insert_front(&(list[current_size]));
      current_size++;
      result = null;
    } else {
      FeatureCacheItem * item = dlist.remove_back();
      auto feature = item.feature;
      *item = new_item;
      dlist.insert_front(item);
      result = feature;
    }
    if (link_features) {
      check_for_children_and_parents(result);
    }
    return result;
  }

  /**
   * Call this method when there are no more records in the data
   * source. Removes and returns the oldest feature in the cache.
   */
  Feature remove_from_back() {
    auto item = dlist.remove_back();
    if (item !is null) {
      if (link_features) {
        check_for_children_and_parents(item.feature);
      }
      return item.feature;
    } else {
      return null;
    }
  }

  private {
    void check_for_children_and_parents(Feature feature) {
      if (feature !is null) {
        bool search_for_parent = ((feature.parent_feature is null) &&
                                  (feature.parent !is null));
        bool search_for_children = feature.id !is null;
        // Search for parents or children
        if (search_for_parent || search_for_children) {
          int feature_hash = hash(feature.id);
          int parent_hash = hash(feature.parent);
          FeatureCacheItem * item = dlist.first;
          while((item !is null) && (search_for_parent || search_for_children)) {
            if (search_for_parent) {
              if (item.id_hash == parent_hash) {
                if (item.feature.id == feature.parent) {
                  feature.set_parent_feature(item.feature);
                  item.feature.add_child(feature);
                  search_for_parent = false;
                }
              }
            }
            if (search_for_children) {
              if (item.parent_hash == feature_hash) {
                if (item.feature.parent == feature.id) {
                  item.feature.set_parent_feature(feature);
                  feature.add_child(item.feature);
                }
              }
            }
            item = item.next;
          }
        }
      }
    }

    DList!FeatureCacheItem dlist;
    FeatureCacheItem[] list;

    size_t max_size;
    bool link_features = false;
    uint current_size = 0;
  }
}

struct FeatureCacheItem {
  int id_hash;
  int parent_hash;
  Feature feature;

  FeatureCacheItem * prev;
  FeatureCacheItem * next;
}

import std.stdio, std.conv;
import bio.gff3.record_range;
import util.split_into_lines;

unittest {
  writeln("Testing FeatureRange...");

  // Test with only one feature
  string test_records = ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=1\n" ~
                        ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=2\n" ~
                        ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=3";
  auto records = new RecordRange!SplitIntoLines(new SplitIntoLines(test_records));
  auto features = new FeatureRange(records);
  assert(features.front.id == "1");
  features.popFront();
  assert(features.empty == true);

  // Test with two features
  test_records = ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=1\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=2\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=1;value=3\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=2;value=1\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=2;value=2\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=2;value=3\n";
  records = new RecordRange!SplitIntoLines(new SplitIntoLines(test_records));
  features = new FeatureRange(records);
  assert(features.empty == false);
  assert(features.front.id == "1");
  assert(features.front.records.length == 3);
  features.popFront();
  assert(features.empty == false);
  assert(features.front.id == "2");
  assert(features.front.records.length == 3);
  features.popFront();
  assert(features.empty == true);

  // Test with more then the default number of features in cache
  foreach(i; 3..1003) {
    foreach(j; 1..4) {
      test_records ~= ".\t.\t.\t.\t.\t.\t.\t.\tID=" ~ to!string(i) ~ ";value=" ~ to!string(j) ~ "\n";
    }
  }
  records = new RecordRange!SplitIntoLines(new SplitIntoLines(test_records));
  features = new FeatureRange(records);
  assert(features.empty == false);
  foreach(i; 1..1003) {
    assert(features.empty == false);
    assert(features.front.id == to!string(i));
    assert(features.front.records.length == 3);
    features.popFront();
  }
  assert(features.empty == true);

  // Retest with a smaller feature cache
  records = new RecordRange!SplitIntoLines(new SplitIntoLines(test_records));
  features = new FeatureRange(records, 97);
  assert(features.empty == false);
  foreach(i; 1..1003) {
    assert(features.empty == false);
    assert(features.front.id == to!string(i));
    assert(features.front.records.length == 3);
    features.popFront();
  }
  assert(features.empty == true);

  // Test parent-child linking
  test_records = ".\t.\t.\t.\t.\t.\t.\t.\tID=1\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=2;Parent=1\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=3;Parent=1\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=4;Parent=2\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=4;Parent=2\n" ~
                 ".\t.\t.\t.\t.\t.\t.\t.\tID=5;Parent=3\n";
  records = new RecordRange!SplitIntoLines(new SplitIntoLines(test_records));
  features = new FeatureRange(records, 10, true);
  assert(features.empty == false);
  uint count_features = 0;
  foreach(feature; features) {
    if (feature.id == "1") {
      assert(feature.parent_feature is null);
      assert(features.front.children.length == 2);
    } else if (feature.id == "2") {
      assert(feature.parent_feature !is null);
      assert(feature.parent_feature.id == "1");
      assert(feature.children.length == 1);
      assert(feature.children[0].id == "4");
    } else if (feature.id == "3") {
      assert(feature.parent_feature !is null);
      assert(feature.parent_feature.id == "1");
      assert(feature.children.length == 1);
      assert(feature.children[0].id == "5");
    } else if (feature.id == "4") {
      assert(feature.parent_feature !is null);
      assert(feature.parent_feature.id == "2");
      assert(feature.children.length == 0);
    } else if (feature.id == "5") {
      assert(feature.parent_feature !is null);
      assert(feature.parent_feature.id == "3");
      assert(feature.children.length == 0);
    }
    count_features++;
  }
  assert(count_features == 5);
}

