//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh |
//|                      Copyright 2025, Javohir Abdullayev          |
//|                                                   Version 1.0    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Javohir Abdullayev"
#property link      "https://pycoder.uz"

//--- Include guards
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Enums
enum ENUM_DASHBOARD_CORNER
  {
   UPPER_LEFT,
   UPPER_RIGHT,
   LOWER_LEFT,
   LOWER_RIGHT
  };

enum ENUM_DASHBOARD_THEME
  {
   THEME_NIGHT,    // Dark theme
   THEME_DAY       // Light theme
  };

//+------------------------------------------------------------------+
//| The CDashboard class                                             |
//+------------------------------------------------------------------+
class CDashboard
{
private:
    string            m_prefix;
    long              m_chart_id;
    int               m_x_pos;
    int               m_y_pos;
    int               m_width;
    int               m_row_height;
    int               m_max_rows;
    int               m_last_row_count;
    ENUM_BASE_CORNER  m_corner;
    ENUM_DASHBOARD_THEME m_theme;

    //--- Style properties
    color             m_bg_color;
    color             m_border_color;
    color             m_header_color;
    color             m_text_color;
    color             m_profit_color;
    color             m_loss_color;
    color             m_line_color;
    int               m_font_size;
    int               m_title_font_size;

    //--- Column widths
    int               m_col1_width;
    int               m_col2_width;
    int               m_col3_width;

    //--- Private methods
    string            GetTradeTypeString(ENUM_POSITION_TYPE pos_type);
    string            GetTradeTypeString(ENUM_ORDER_TYPE order_type);
    void              UpdateCell(int row, int col, string text, color text_color, bool create_bg=true, int font_size_override=0, ENUM_ANCHOR_POINT align=ANCHOR_LEFT_UPPER);
    void              ClearRow(int row);
    void              ApplyTheme(ENUM_DASHBOARD_THEME theme);

public:
                      CDashboard(void);
                     ~CDashboard(void);

    void              Create(long chart_id, string prefix, int x, int y, int width, ENUM_DASHBOARD_CORNER corner, ENUM_DASHBOARD_THEME theme, int max_rows=15);
    void              Update(ulong initial_pos_ticket, ulong ea_magic);
    void              Destroy();
    void              SetTheme(ENUM_DASHBOARD_THEME theme);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDashboard::CDashboard(void) :
    m_chart_id(0),
    m_x_pos(20),
    m_y_pos(50),
    m_width(450),
    m_row_height(20),
    m_max_rows(15),
    m_last_row_count(0),
    m_corner(CORNER_LEFT_UPPER),
    m_theme(THEME_NIGHT),
    m_bg_color(C'26,32,44'),
    m_border_color(C'42,52,70'),
    m_header_color(C'150,160,180'),
    m_text_color(clrWhite),
    m_profit_color(C'76,175,80'),
    m_loss_color(C'244,67,54'),
    m_line_color(C'60,70,90'),
    m_font_size(8),
    m_title_font_size(10)
{
}

CDashboard::~CDashboard(void){}

//+------------------------------------------------------------------+
//| Create the dashboard's static elements                           |
//+------------------------------------------------------------------+
void CDashboard::Create(long chart_id, string prefix, int x, int y, int width, ENUM_DASHBOARD_CORNER corner, ENUM_DASHBOARD_THEME theme, int max_rows=15)
{
    m_chart_id = chart_id;
    m_prefix = prefix;
    m_x_pos = x;
    m_y_pos = y;
    m_width = width;
    m_max_rows = max_rows;
    
    //--- Apply theme
    ApplyTheme(theme);

    switch(corner)
    {
        case UPPER_RIGHT: m_corner = CORNER_RIGHT_UPPER; break;
        case LOWER_LEFT:  m_corner = CORNER_LEFT_LOWER;  break;
        case LOWER_RIGHT: m_corner = CORNER_RIGHT_LOWER; break;
        default:          m_corner = CORNER_LEFT_UPPER;  break;
    }

    m_col1_width = (int)(m_width * 0.45);
    m_col2_width = (int)(m_width * 0.25);
    m_col3_width = m_width - m_col1_width - m_col2_width;

    //--- Create Title and Headers
    UpdateCell(0, 0, "Hedging Ping-Pong Status", m_header_color, true, m_title_font_size, ANCHOR_CENTER);
    UpdateCell(1, 0, "Order",       m_header_color);
    UpdateCell(1, 1, "Status",      m_header_color);
    UpdateCell(1, 2, "P/L",         m_header_color, true, 0, ANCHOR_RIGHT_UPPER);
}

//+------------------------------------------------------------------+
//| Update the dynamic data of the dashboard                         |
//+------------------------------------------------------------------+
void CDashboard::Update(ulong initial_pos_ticket, ulong ea_magic)
{
    int row = 2; // Start after title and header
    double total_profit = 0;
    string symbol = Symbol();

    CPositionInfo pos;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Symbol() == symbol && (pos.Magic() == ea_magic || pos.Ticket() == initial_pos_ticket))
            {
                if(row >= m_max_rows) break;
                
                string desc = GetTradeTypeString(pos.PositionType()) + " " + DoubleToString(pos.Volume(), 2);
                double profit = pos.Profit();
                total_profit += profit;
                color pnl_color = (profit >= 0) ? m_profit_color : m_loss_color;
                
                UpdateCell(row, 0, desc, m_text_color);
                UpdateCell(row, 1, "Active", m_text_color);
                UpdateCell(row, 2, DoubleToString(profit, 2), pnl_color, true, 0, ANCHOR_RIGHT_UPPER);
                row++;
            }
        }
    }

    COrderInfo order;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(order.SelectByIndex(i))
        {
            if(order.Symbol() == symbol && order.Magic() == ea_magic)
            {
                if(row >= m_max_rows) break;

                // Get order type - using TypeDescription() for accuracy
                string type_desc = order.TypeDescription();
                string desc = type_desc + " " + DoubleToString(order.VolumeInitial(), 2);
                string price_str = " @ " + DoubleToString(order.PriceOpen(), (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
                desc += price_str;
                
                UpdateCell(row, 0, desc, m_text_color);
                UpdateCell(row, 1, "Pending", m_text_color);
                UpdateCell(row, 2, "---", m_text_color, true, 0, ANCHOR_RIGHT_UPPER);
                row++;
            }
        }
    }

    if(row < m_max_rows)
    {
        color total_pnl_color = (total_profit >= 0) ? m_profit_color : m_loss_color;
        UpdateCell(row, 0, "", m_text_color, false);
        UpdateCell(row, 1, "Total P/L:", m_header_color, false, 0, ANCHOR_RIGHT_UPPER);
        UpdateCell(row, 2, DoubleToString(total_profit, 2), total_pnl_color, false, 0, ANCHOR_RIGHT_UPPER);
        row++;
    }

    for(int i = row; i < m_last_row_count; i++)
    {
        ClearRow(i);
    }
    m_last_row_count = row;
    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Destroy all dashboard objects                                    |
//+------------------------------------------------------------------+
void CDashboard::Destroy()
{
    ObjectsDeleteAll(m_chart_id, m_prefix);
    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Apply theme to dashboard                                         |
//+------------------------------------------------------------------+
void CDashboard::ApplyTheme(ENUM_DASHBOARD_THEME theme)
{
    m_theme = theme;
    
    if(theme == THEME_NIGHT)
    {
        //--- Night Theme (Dark)
        m_bg_color = C'26,32,44';           // Dark blue-gray background
        m_border_color = C'42,52,70';       // Slightly lighter border
        m_header_color = C'150,160,180';    // Light gray-blue headers
        m_text_color = clrWhiteSmoke;       // Off-white text
        m_profit_color = C'76,175,80';      // Green for profit
        m_loss_color = C'244,67,54';        // Red for loss
        m_line_color = C'60,70,90';         // Separator line color
    }
    else // THEME_DAY
    {
        //--- Day Theme (Light)
        m_bg_color = C'245,245,245';        // Light gray background
        m_border_color = C'200,200,200';    // Medium gray border
        m_header_color = C'50,50,50';       // Dark gray headers
        m_text_color = C'33,33,33';         // Almost black text
        m_profit_color = C'34,139,34';      // Forest green for profit
        m_loss_color = C'178,34,34';        // Firebrick red for loss
        m_line_color = C'180,180,180';      // Light separator line
    }
}

//+------------------------------------------------------------------+
//| Set theme and update dashboard                                   |
//+------------------------------------------------------------------+
void CDashboard::SetTheme(ENUM_DASHBOARD_THEME theme)
{
    ApplyTheme(theme);
    
    //--- Recreate headers with new colors
    UpdateCell(0, 0, "Hedging Ping-Pong Status", m_header_color, true, m_title_font_size, ANCHOR_CENTER);
    UpdateCell(1, 0, "Order",       m_header_color);
    UpdateCell(1, 1, "Status",      m_header_color);
    UpdateCell(1, 2, "P/L",         m_header_color, true, 0, ANCHOR_RIGHT_UPPER);
    
    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Convert Position Type to readable string                         |
//+------------------------------------------------------------------+
string CDashboard::GetTradeTypeString(ENUM_POSITION_TYPE pos_type)
{
    switch(pos_type)
    {
        case POSITION_TYPE_BUY:  return "Buy";
        case POSITION_TYPE_SELL: return "Sell";
    }
    return "Unknown";
}

//+------------------------------------------------------------------+
//| Convert Order Type to readable string                            |
//+------------------------------------------------------------------+
string CDashboard::GetTradeTypeString(ENUM_ORDER_TYPE order_type)
{
    switch(order_type)
    {
        case ORDER_TYPE_BUY:        return "Buy";
        case ORDER_TYPE_SELL:       return "Sell";
        case ORDER_TYPE_BUY_LIMIT:  return "Buy Limit";
        case ORDER_TYPE_BUY_STOP:   return "Buy Stop";
        case ORDER_TYPE_SELL_LIMIT: return "Sell Limit";
        case ORDER_TYPE_SELL_STOP:  return "Sell Stop";
        case ORDER_TYPE_BUY_STOP_LIMIT: return "Buy Stop Limit";
        case ORDER_TYPE_SELL_STOP_LIMIT: return "Sell Stop Limit";
    }
    return "Unknown [" + IntegerToString(order_type) + "]";
}

//+------------------------------------------------------------------+
//| Create or update a single cell in the dashboard                  |
//+------------------------------------------------------------------+
void CDashboard::UpdateCell(int row, int col, string text, color text_color, bool create_bg=true, int font_size_override=0, ENUM_ANCHOR_POINT align=ANCHOR_LEFT_UPPER)
{
    int x_offset = 0;
    int current_width = 0;
    if(col == 0) { current_width = m_col1_width; x_offset = 0; }
    else if(col == 1) { current_width = m_col2_width; x_offset = m_col1_width; }
    else { current_width = m_col3_width; x_offset = m_col1_width + m_col2_width; }
    
    if(row == 0 && col == 0) current_width = m_width;

    string bg_name = m_prefix + "_bg_" + (string)row + "_" + (string)col;
    string text_name = m_prefix + "_text_" + (string)row + "_" + (string)col;
    
    if(create_bg)
    {
        if(ObjectFind(m_chart_id, bg_name) != 0)
        {
            ObjectCreate(m_chart_id, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_XSIZE, current_width);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_YSIZE, m_row_height);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_CORNER, m_corner);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_BACK, true);
        }
        ObjectSetInteger(m_chart_id, bg_name, OBJPROP_XDISTANCE, m_x_pos + x_offset);
        ObjectSetInteger(m_chart_id, bg_name, OBJPROP_YDISTANCE, m_y_pos + row * m_row_height);
        ObjectSetInteger(m_chart_id, bg_name, OBJPROP_BGCOLOR, (row <= 1) ? m_border_color : m_bg_color);
        ObjectSetInteger(m_chart_id, bg_name, OBJPROP_COLOR, m_line_color);
    }

    if(ObjectFind(m_chart_id, text_name) != 0)
    {
        ObjectCreate(m_chart_id, text_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chart_id, text_name, OBJPROP_CORNER, m_corner);
        ObjectSetString(m_chart_id, text_name, OBJPROP_FONT, "Calibri");
    }
    
    int font_size = (font_size_override > 0) ? font_size_override : m_font_size;
    int text_x = m_x_pos + x_offset;
    if(align == ANCHOR_LEFT_UPPER) text_x += 5;
    else if(align == ANCHOR_CENTER) text_x += current_width / 2;
    else if(align == ANCHOR_RIGHT_UPPER) text_x += current_width - 5;

    ObjectSetInteger(m_chart_id, text_name, OBJPROP_XDISTANCE, text_x);
    ObjectSetInteger(m_chart_id, text_name, OBJPROP_YDISTANCE, m_y_pos + row * m_row_height + m_row_height/2 - font_size/2-1);
    ObjectSetInteger(m_chart_id, text_name, OBJPROP_ANCHOR, align);
    ObjectSetInteger(m_chart_id, text_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetString(m_chart_id, text_name, OBJPROP_TEXT, text);
    ObjectSetInteger(m_chart_id, text_name, OBJPROP_COLOR, text_color);
}

//+------------------------------------------------------------------+
//| Clears a row's text content                                      |
//+------------------------------------------------------------------+
void CDashboard::ClearRow(int row)
{
    for(int col = 0; col < 3; col++)
    {
        string bg_name = m_prefix + "_bg_" + (string)row + "_" + (string)col;
        string text_name = m_prefix + "_text_" + (string)row + "_" + (string)col;
        if(ObjectFind(m_chart_id, text_name) == 0) ObjectSetString(m_chart_id, text_name, OBJPROP_TEXT, "");
        if(ObjectFind(m_chart_id, bg_name) == 0)
        {
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_BGCOLOR, clrNONE);
            ObjectSetInteger(m_chart_id, bg_name, OBJPROP_COLOR, clrNONE);
        }
    }
}

#endif // DASHBOARD_MQH
